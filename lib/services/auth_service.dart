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
          if (displayName != null && displayName.isNotEmpty) 'full_name': displayName.trim(),
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
      await _client.auth.signInWithOtp(
        phone: phone.trim(),
      );
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

  Future<AuthResponse> signInWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
      );

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw Exception('Google sign-in was cancelled by user');
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw Exception('Failed to obtain Google ID Token');
      }

      return await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
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
      await _client.auth.resend(
        type: OtpType.signup,
        email: email.trim(),
      );
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
