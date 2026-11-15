import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../core/errors/app_failure.dart';
import '../core/errors/failure_messages.dart';
import '../core/logging/app_logger.dart';
import '../core/storage/preferences.dart';
import '../core/utils/haptics.dart';
import '../data/repositories/account_repository.dart';
import '../models/json_reader.dart';
import '../services/auth_service.dart';

enum AuthStatus { initial, authenticated, unauthenticated }

/// Who is signed in. Profile data lives in `profileProvider`.
class AppAuthState {
  const AppAuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.failure,
    this.isLoading = false,
  });

  final AuthStatus status;
  final supabase.User? user;

  /// The last action's failure, shown inline on the auth screens.
  final AppFailure? failure;
  final bool isLoading;

  /// Friendly copy for [failure]; never a raw exception string.
  String? get errorMessage =>
      failure == null ? null : friendlyMessage(failure!);

  bool get isAuthenticated =>
      status == AuthStatus.authenticated && user != null;

  bool get isEmailVerified {
    final confirmed = user?.emailConfirmedAt;
    return confirmed != null && confirmed.isNotEmpty;
  }

  AppAuthState copyWith({
    AuthStatus? status,
    Object? user = unset,
    Object? failure = unset,
    bool? isLoading,
  }) {
    return AppAuthState(
      status: status ?? this.status,
      user: pick<supabase.User?>(user, this.user),
      failure: pick<AppFailure?>(failure, this.failure),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService.instance,
);

/// Auth state. The Supabase auth stream is the source of truth for who is
/// signed in; actions only add loading and failure information (and the
/// user returned by a sign-up that has no session yet).
class AuthNotifier extends Notifier<AppAuthState> {
  AuthService get _service => ref.read(authServiceProvider);

  @override
  AppAuthState build() {
    final service = ref.watch(authServiceProvider);

    final sub = service.authStateChanges.listen(
      _onAuthEvent,
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.warn('Auth stream error', ErrorMapper.map(error, stackTrace));
      },
    );
    ref.onDispose(sub.cancel);

    // When a user leaves (sign-out, deletion, switch), wipe their
    // per-user device data. The theme is device-wide and stays.
    listenSelf((previous, next) {
      final left = previous?.user?.id;
      if (left != null && left != next.user?.id) {
        unawaited(_clearUserData(left));
      }
    });

    final user = service.currentUser;
    return AppAuthState(
      status: user == null
          ? AuthStatus.unauthenticated
          : AuthStatus.authenticated,
      user: user,
    );
  }

  void _onAuthEvent(supabase.AuthState data) {
    if (!ref.mounted) return;
    final user = data.session?.user;
    switch (data.event) {
      case supabase.AuthChangeEvent.signedOut:
        _setSignedOut();
      default:
        if (user != null) {
          state = state.copyWith(status: AuthStatus.authenticated, user: user);
        } else if (data.event == supabase.AuthChangeEvent.initialSession &&
            state.user == null) {
          state = state.copyWith(status: AuthStatus.unauthenticated);
        }
    }
  }

  void _setSignedOut() {
    state = const AppAuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> _clearUserData(String userId) async {
    AppHaptics.isEnabled = true;
    try {
      await UserPrefs.clearUser(ref.read(sharedPreferencesProvider), userId);
    } on Object catch (e) {
      AppLogger.warn('Could not clear user preferences', e.runtimeType);
    }
  }

  /// Runs [action] with loading and failure handling. Returns the failure,
  /// or null on success.
  Future<AppFailure?> _run(Future<void> Function() action) async {
    state = state.copyWith(isLoading: true, failure: null);
    AppHaptics.light();
    try {
      await action();
      if (ref.mounted) state = state.copyWith(isLoading: false);
      AppHaptics.success();
      return null;
    } catch (error, stackTrace) {
      final failure = error is GoogleSignInUnavailableException
          ? const AppFailure.business('google_unavailable')
          : ErrorMapper.map(error, stackTrace);
      if (ref.mounted) {
        state = state.copyWith(isLoading: false, failure: failure);
      }
      AppHaptics.error();
      return failure;
    }
  }

  void _signedIn(supabase.User? user) {
    if (user == null || !ref.mounted) return;
    state = state.copyWith(status: AuthStatus.authenticated, user: user);
  }

  void clearError() {
    if (state.failure != null) state = state.copyWith(failure: null);
  }

  Future<AppFailure?> signInWithEmail(String email, String password) => _run(
    () async => _signedIn(
      (await _service.signInWithEmail(email: email, password: password)).user,
    ),
  );

  Future<AppFailure?> signUpWithEmail(
    String email,
    String password,
    String displayName,
  ) => _run(
    () async => _signedIn(
      (await _service.signUpWithEmail(
        email: email,
        password: password,
        displayName: displayName,
      )).user,
    ),
  );

  Future<AppFailure?> signInWithGoogle() => _run(() async {
    final response = await _service.signInWithGoogle();
    // Null means the user closed the account picker: nothing to report.
    _signedIn(response?.user);
  });

  Future<AppFailure?> signInWithApple() =>
      _run(() async => _signedIn((await _service.signInWithApple()).user));

  Future<AppFailure?> sendPasswordReset(String email) =>
      _run(() => _service.sendPasswordResetEmail(email));

  Future<AppFailure?> updatePassword(String newPassword) =>
      _run(() async => _service.updatePassword(newPassword));

  Future<AppFailure?> resendVerificationEmail() async {
    final email = state.user?.email;
    if (email == null || email.isEmpty) return null;
    return _run(() => _service.resendVerificationEmail(email));
  }

  /// Re-reads the user to see whether the email is confirmed now.
  Future<bool> refreshEmailVerificationStatus() async {
    await _run(() async {
      final response = await _service.refreshSession();
      _signedIn(response.user ?? _service.currentUser);
    });
    return ref.mounted && state.isEmailVerified;
  }

  /// Signs out locally even when the server call fails.
  Future<void> signOut() async {
    state = state.copyWith(isLoading: true, failure: null);
    try {
      await _service.signOut();
    } finally {
      if (ref.mounted) _setSignedOut();
    }
  }

  /// Deletes the account on the server, then signs out. On failure the
  /// session is kept and the failure is returned.
  Future<AppFailure?> deleteAccount() async {
    state = state.copyWith(isLoading: true, failure: null);
    try {
      await ref.read(accountRepositoryProvider).deleteAccount();
    } on AppFailure catch (failure) {
      if (ref.mounted) state = state.copyWith(isLoading: false);
      return failure;
    }
    await signOut();
    return null;
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AppAuthState>(
  AuthNotifier.new,
);

/// The signed-in, verified user's id, or null. Every user-scoped provider
/// watches this, so a sign-out or user switch rebuilds them with no data
/// from the previous user.
final currentUserIdProvider = Provider<String?>((ref) {
  final auth = ref.watch(authNotifierProvider);
  return auth.isAuthenticated && auth.isEmailVerified ? auth.user!.id : null;
});
