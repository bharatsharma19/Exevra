import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Authentication Service handling Email/Password, Phone OTP, Google, and Apple Sign-Ins
class AuthService {
  static AuthService? _instance;
  static AuthService get instance => _instance ??= AuthService._();

  AuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;
  Session? get currentSession => _client.auth.currentSession;
  bool get isAuthenticated => currentUser != null;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // ---------------------------------------------------------------------------
  // EMAIL & PASSWORD AUTHENTICATION
  // ---------------------------------------------------------------------------

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          if (displayName != null && displayName.isNotEmpty)
            'full_name': displayName.trim(),
        },
      );
      return response;
    } catch (e) {
      debugPrint('[AuthService] signUpWithEmail error: $e');
      rethrow;
    }
  }

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      return response;
    } catch (e) {
      debugPrint('[AuthService] signInWithEmail error: $e');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // PHONE SMS OTP AUTHENTICATION
  // ---------------------------------------------------------------------------

  Future<void> sendPhoneOtp(String phone) async {
    try {
      await _client.auth.signInWithOtp(phone: phone.trim());
    } catch (e) {
      debugPrint('[AuthService] sendPhoneOtp error: $e');
      rethrow;
    }
  }

  Future<AuthResponse> verifyPhoneOtp({
    required String phone,
    required String token,
  }) async {
    try {
      final response = await _client.auth.verifyOTP(
        phone: phone.trim(),
        token: token.trim(),
        type: OtpType.sms,
      );
      return response;
    } catch (e) {
      debugPrint('[AuthService] verifyPhoneOtp error: $e');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // SOCIAL SIGN-INS: GOOGLE & APPLE
  // ---------------------------------------------------------------------------

  static const String _googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );
  static const String _googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );
  static const List<String> _googleScopes = ['email', 'profile'];

  Future<void>? _googleInit;

  /// Whether Google sign-in has the client configuration it needs.
  bool get isGoogleSignInConfigured => _googleWebClientId.isNotEmpty;

  Future<void> _ensureGoogleInitialized() {
    return _googleInit ??= GoogleSignIn.instance.initialize(
      serverClientId: _googleWebClientId,
      clientId: _googleIosClientId.isEmpty ? null : _googleIosClientId,
    );
  }

  /// Signs in with Google and exchanges the ID token with Supabase.
  ///
  /// Returns `null` when the user cancels the Google account picker.
  /// Throws [GoogleSignInUnavailableException] when the build carries no
  /// Google client configuration.
  Future<AuthResponse?> signInWithGoogle() async {
    if (!isGoogleSignInConfigured) {
      throw const GoogleSignInUnavailableException();
    }
    try {
      await _ensureGoogleInitialized();
      final googleSignIn = GoogleSignIn.instance;

      final GoogleSignInAccount account = await googleSignIn.authenticate(
        scopeHint: _googleScopes,
      );

      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw Exception('Failed to obtain Google ID Token');
      }

      final authorization = await account.authorizationClient
          .authorizationForScopes(_googleScopes);

      return await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: authorization?.accessToken,
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      debugPrint('[AuthService] Google Sign-In: ${e.code}');
      rethrow;
    } catch (e) {
      debugPrint('[AuthService] Google Sign-In: $e');
      rethrow;
    }
  }

  Future<AuthResponse> signInWithApple() async {
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final idToken = appleCredential.identityToken;
      if (idToken == null) {
        throw Exception('Failed to obtain Apple Identity Token');
      }

      return await _client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
      );
    } catch (e) {
      debugPrint('[AuthService] Apple Sign-In: $e');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // PASSWORD RECOVERY & RESET
  // ---------------------------------------------------------------------------

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: 'io.antigravity.expensemanager://reset-password',
      );
    } catch (e) {
      debugPrint('[AuthService] sendPasswordResetEmail error: $e');
      rethrow;
    }
  }

  Future<UserResponse> updatePassword(String newPassword) async {
    try {
      return await _client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
    } catch (e) {
      debugPrint('[AuthService] updatePassword error: $e');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // EMAIL VERIFICATION & SESSION REFRESH
  // ---------------------------------------------------------------------------

  Future<AuthResponse> refreshSession() async {
    try {
      final response = await _client.auth.refreshSession();
      return response;
    } catch (e) {
      debugPrint('[AuthService] refreshSession error: $e');
      rethrow;
    }
  }

  Future<void> resendVerificationEmail(String email) async {
    try {
      await _client.auth.resend(type: OtpType.signup, email: email.trim());
    } catch (e) {
      debugPrint('[AuthService] resendVerificationEmail error: $e');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // SIGN OUT
  // ---------------------------------------------------------------------------

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      debugPrint('[AuthService] signOut error: $e');
    }
  }
}

/// Thrown when Google sign-in is not configured for this build.
class GoogleSignInUnavailableException implements Exception {
  const GoogleSignInUnavailableException();

  @override
  String toString() => 'Google sign-in is not available right now.';
}
