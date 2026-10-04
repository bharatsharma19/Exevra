import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/haptics.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AppAuthState {
  final AuthStatus status;
  final supabase.User? user;
  final UserProfile? profile;
  final String? errorMessage;
  final bool isLoading;
  final String themeMode;

  const AppAuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.profile,
    this.errorMessage,
    this.isLoading = false,
    this.themeMode = 'system',
  });

  bool get isAuthenticated => status == AuthStatus.authenticated && user != null;

  bool get isEmailVerified {
    if (user == null) return false;
    // Phone users without email registered are not gated by email verification
    if ((user!.email == null || user!.email!.isEmpty) && user!.phone != null) {
      return true;
    }
    return user!.emailConfirmedAt != null && user!.emailConfirmedAt!.isNotEmpty;
  }

  AppAuthState copyWith({
    AuthStatus? status,
    supabase.User? user,
    UserProfile? profile,
    Object? errorMessage = const Object(),
    bool? isLoading,
    String? themeMode,
  }) {
    return AppAuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      profile: profile ?? this.profile,
      errorMessage: errorMessage == const Object() ? this.errorMessage : errorMessage as String?,
      isLoading: isLoading ?? this.isLoading,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

class AuthNotifier extends StateNotifier<AppAuthState> {
  final AuthService _authService;
  final SupabaseService _supabaseService;
  StreamSubscription<supabase.AuthState>? _authSub;

  AuthNotifier(this._authService, this._supabaseService) : super(const AppAuthState()) {
    _init();
  }

  Future<void> _init() async {
    state = state.copyWith(isLoading: true);

    String cachedCurrency = AppConstants.defaultCurrency;
    String cachedTheme = 'system';
    bool cachedHaptics = true;
    bool cachedAiConsent = false;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      cachedCurrency = prefs.getString(AppConstants.keyCurrency) ?? AppConstants.defaultCurrency;
      cachedTheme = prefs.getString(AppConstants.keyThemeMode) ?? 'system';
      cachedHaptics = prefs.getBool(AppConstants.keyHapticsEnabled) ?? true;
      cachedAiConsent = prefs.getBool(AppConstants.keyAiConsent) ?? false;
    } catch (e) {
      debugPrint('[AuthNotifier] Failed to load preferences: $e');
    }
    
    AppHaptics.isEnabled = cachedHaptics;

    final currentUser = _authService.currentUser;
    if (currentUser != null) {
      final profile = await _supabaseService.fetchProfile(currentUser.id);
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: currentUser,
        themeMode: cachedTheme,
        profile: profile?.copyWith(
          currency: cachedCurrency,
          themeMode: cachedTheme,
          hapticsEnabled: cachedHaptics,
          aiConsent: cachedAiConsent,
        ),
        isLoading: false,
      );
    } else {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        themeMode: cachedTheme,
        isLoading: false,
      );
    }

    _authSub = _authService.authStateChanges.listen((data) async {
      final user = data.session?.user;
      final event = data.event;

      if (event == supabase.AuthChangeEvent.signedOut) {
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          user: null,
          profile: null,
          isLoading: false,
        );
      } else if (user != null) {
        if (state.user?.id != user.id || state.profile == null) {
          final profile = await _supabaseService.fetchProfile(user.id);
          state = state.copyWith(
            status: AuthStatus.authenticated,
            user: user,
            profile: profile,
            isLoading: false,
          );
        } else {
          state = state.copyWith(
            status: AuthStatus.authenticated,
            user: user,
            isLoading: false,
          );
        }
      } else if (event == supabase.AuthChangeEvent.initialSession) {
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          user: null,
          profile: null,
          isLoading: false,
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // AUTH ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> signInWithEmail(String email, String password) async {
    try {
      state = state.copyWith(isLoading: true, errorMessage: null);
      AppHaptics.light();
      final res = await _authService.signInWithEmail(email: email, password: password);
      final user = res.user;
      if (user != null) {
        final profile = await _supabaseService.fetchProfile(user.id);
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          profile: profile,
          isLoading: false,
        );
        AppHaptics.success();
      }
    } catch (e) {
      final isDemoUrl = _supabaseService.isDemoMode;
      if (isDemoUrl && (e.toString().contains('Invalid login credentials') || e.toString().contains('Failed host lookup'))) {
        _enterDemoSession(email);
        return;
      }
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: e.toString().replaceAll('Exception:', '').replaceAll('AuthException:', '').trim(),
        isLoading: false,
      );
      AppHaptics.error();
    }
  }

  Future<void> signUpWithEmail(String email, String password, String displayName) async {
    try {
      state = state.copyWith(isLoading: true, errorMessage: null);
      AppHaptics.light();
      final res = await _authService.signUpWithEmail(
        email: email,
        password: password,
        displayName: displayName,
      );
      final user = res.user;
      if (user != null) {
        final profile = await _supabaseService.fetchProfile(user.id);
        final effectiveName = displayName.trim().isNotEmpty ? displayName.trim() : email.split('@').first;
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          profile: (profile ?? UserProfile(
            id: user.id,
            displayName: effectiveName,
            email: email.trim(),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          )).copyWith(displayName: effectiveName),
          isLoading: false,
        );
        AppHaptics.success();
      }
    } catch (e) {
      final isDemoUrl = _supabaseService.isDemoMode;
      if (isDemoUrl && (e.toString().contains('Failed host lookup') ||
          e.toString().contains('Network') ||
          e.toString().contains('Invalid API key') ||
          e.toString().contains('ClientException'))) {
        _enterDemoSession(email, displayName: displayName, isVerified: false);
        return;
      }
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: e.toString().replaceAll('Exception:', '').replaceAll('AuthException:', '').trim(),
        isLoading: false,
      );
      AppHaptics.error();
    }
  }

  Future<void> sendPhoneOtp(String phone) async {
    try {
      state = state.copyWith(isLoading: true, errorMessage: null);
      AppHaptics.light();
      await _authService.sendPhoneOtp(phone);
      state = state.copyWith(isLoading: false);
      AppHaptics.success();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception:', '').trim(),
      );
      AppHaptics.error();
    }
  }

  Future<void> verifyPhoneOtp(String phone, String token) async {
    try {
      state = state.copyWith(isLoading: true, errorMessage: null);
      AppHaptics.light();
      final res = await _authService.verifyPhoneOtp(phone: phone, token: token);
      final user = res.user;
      if (user != null) {
        final profile = await _supabaseService.fetchProfile(user.id);
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          profile: profile,
          isLoading: false,
        );
        AppHaptics.success();
      }
    } catch (e) {
      if (_supabaseService.isDemoMode && token == '123456') {
        _enterDemoSession('phone-user@antigravity.io', displayName: 'Phone User', phone: phone);
        return;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception:', '').trim(),
      );
      AppHaptics.error();
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      state = state.copyWith(isLoading: true, errorMessage: null);
      AppHaptics.light();
      final res = await _authService.signInWithGoogle();
      final user = res.user;
      if (user != null) {
        final profile = await _supabaseService.fetchProfile(user.id);
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          profile: profile,
          isLoading: false,
        );
        AppHaptics.success();
      }
    } catch (e) {
      debugPrint('[AuthNotifier] Google sign-in error: $e');
      final isDemoUrl = _supabaseService.isDemoMode;
      if (isDemoUrl) {
        _enterDemoSession('google.user@antigravity.io', displayName: 'Google User');
        return;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Google Sign-In failed: ${e.toString().replaceAll('Exception:', '').trim()}',
      );
      AppHaptics.error();
    }
  }

  Future<void> signInWithApple() async {
    try {
      state = state.copyWith(isLoading: true, errorMessage: null);
      AppHaptics.light();
      final res = await _authService.signInWithApple();
      final user = res.user;
      if (user != null) {
        final profile = await _supabaseService.fetchProfile(user.id);
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          profile: profile,
          isLoading: false,
        );
        AppHaptics.success();
      }
    } catch (e) {
      debugPrint('[AuthNotifier] Apple sign-in error: $e');
      final isDemoUrl = _supabaseService.isDemoMode;
      if (isDemoUrl) {
        _enterDemoSession('apple.user@antigravity.io', displayName: 'Apple User');
        return;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Apple Sign-In failed: ${e.toString().replaceAll('Exception:', '').trim()}',
      );
      AppHaptics.error();
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      state = state.copyWith(isLoading: true, errorMessage: null);
      AppHaptics.light();
      await _authService.sendPasswordResetEmail(email);
      state = state.copyWith(isLoading: false);
      AppHaptics.success();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception:', '').trim(),
      );
      AppHaptics.error();
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      state = state.copyWith(isLoading: true, errorMessage: null);
      AppHaptics.light();
      await _authService.updatePassword(newPassword);
      state = state.copyWith(isLoading: false);
      AppHaptics.success();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception:', '').trim(),
      );
      AppHaptics.error();
    }
  }

  // ---------------------------------------------------------------------------
  // PROFILE & PREFERENCE MUTATIONS
  // ---------------------------------------------------------------------------

  Future<void> updateProfile(UserProfile updated) async {
    state = state.copyWith(profile: updated);
    await _supabaseService.updateProfile(updated);
  }

  Future<void> setActiveGroupId(String? groupId) async {
    if (state.profile != null) {
      final updated = state.profile!.copyWith(groupId: groupId);
      state = state.copyWith(profile: updated);
      await _supabaseService.switchActiveGroup(groupId);
    }
  }

  Future<void> refreshProfile() async {
    final uid = state.user?.id;
    if (uid != null) {
      final p = await _supabaseService.fetchProfile(uid);
      if (p != null) {
        state = state.copyWith(profile: p);
      }
    }
  }

  Future<void> setThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyThemeMode, mode);
    state = state.copyWith(themeMode: mode);
    if (state.profile != null) {
      final updated = state.profile!.copyWith(themeMode: mode);
      await updateProfile(updated);
    }
  }

  Future<void> setCurrency(String currency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyCurrency, currency);
    if (state.profile != null) {
      final updated = state.profile!.copyWith(currency: currency);
      await updateProfile(updated);
    }
  }

  Future<void> setHapticsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyHapticsEnabled, enabled);
    AppHaptics.isEnabled = enabled;
    if (state.profile != null) {
      final updated = state.profile!.copyWith(hapticsEnabled: enabled);
      await updateProfile(updated);
    }
  }

  Future<void> setAiConsent(bool consent) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyAiConsent, consent);
    if (state.profile != null) {
      final updated = state.profile!.copyWith(aiConsent: consent);
      await updateProfile(updated);
    }
  }

  Future<void> deleteAccount() async {
    state = state.copyWith(isLoading: true);
    await _supabaseService.deleteUserAccount();
    state = const AppAuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);
    await _authService.signOut();
    state = const AppAuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> resendVerificationEmail() async {
    final email = state.user?.email;
    if (email == null || email.isEmpty) return;

    try {
      state = state.copyWith(isLoading: true, errorMessage: null);
      AppHaptics.light();
      await _authService.resendVerificationEmail(email);
      state = state.copyWith(isLoading: false);
      AppHaptics.success();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception:', '').trim(),
      );
      AppHaptics.error();
    }
  }

  Future<bool> refreshEmailVerificationStatus() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _authService.refreshSession();
      final refreshedUser = res.user ?? _authService.currentUser;
      if (refreshedUser != null) {
        state = state.copyWith(
          user: refreshedUser,
          isLoading: false,
        );
        if (state.isEmailVerified) {
          AppHaptics.success();
          return true;
        }
      }
    } catch (e) {
      debugPrint('[AuthNotifier] refreshSession fallback: $e');
      // In offline / demo sandbox: activate email verification on explicit refresh
      if (_supabaseService.isDemoMode && state.user != null) {
        final verifiedUser = supabase.User(
          id: state.user!.id,
          appMetadata: state.user!.appMetadata,
          userMetadata: state.user!.userMetadata,
          aud: state.user!.aud,
          createdAt: state.user!.createdAt,
          email: state.user!.email,
          phone: state.user!.phone,
          emailConfirmedAt: DateTime.now().toIso8601String(),
        );
        state = state.copyWith(
          user: verifiedUser,
          isLoading: false,
        );
        AppHaptics.success();
        return true;
      }
    }
    state = state.copyWith(isLoading: false);
    return state.isEmailVerified;
  }

  void _enterDemoSession(String email, {String? displayName, String? phone, bool isVerified = true}) {
    final stubProfile = UserProfile(
      id: 'demo-user-id',
      displayName: displayName ?? email.split('@').first,
      email: email,
      phone: phone,
      groupId: 'grp-demo',
      currency: AppConstants.defaultCurrency,
      themeMode: 'system',
      hapticsEnabled: true,
      aiConsent: true,
      createdAt: DateTime.now().subtract(const Duration(days: 30)),
      updatedAt: DateTime.now(),
    );
    state = state.copyWith(
      status: AuthStatus.authenticated,
      user: supabase.User(
        id: 'demo-user-id',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        email: email,
        phone: phone,
        emailConfirmedAt: isVerified ? DateTime.now().toIso8601String() : null,
      ),
      profile: stubProfile,
      isLoading: false,
      errorMessage: null,
    );
    AppHaptics.success();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService.instance);
final supabaseServiceProvider = Provider<SupabaseService>((ref) => SupabaseService.instance);

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AppAuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  final supabaseService = ref.watch(supabaseServiceProvider);
  return AuthNotifier(authService, supabaseService);
});

final userProfileProvider = Provider<UserProfile?>((ref) {
  return ref.watch(authNotifierProvider).profile;
});
