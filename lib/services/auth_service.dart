import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../core/errors/app_failure.dart';
import '../core/logging/app_logger.dart';
import '../core/security/nonce.dart';
import '../data/supabase_client_provider.dart';

/// Outcome of an email sign-up.
enum SignUpOutcome {
  /// The server returned a session (email confirmation is off).
  signedIn,

  /// The account was created and a confirmation email (link and 6-digit
  /// code) was sent. There is no session until the email is confirmed.
  confirmationSent,

  /// The address is already registered. With confirmations on, the server
  /// hides this by returning a user with no identities.
  alreadyRegistered,
}

/// The name Apple shares on the first authorisation only.
@immutable
class AppleName {
  const AppleName({this.givenName, this.familyName});

  final String? givenName;
  final String? familyName;

  /// "Given Family", or null when Apple shared no name.
  String? get fullName {
    final parts = [
      givenName,
      familyName,
    ].map((p) => p?.trim() ?? '').where((p) => p.isNotEmpty);
    return parts.isEmpty ? null : parts.join(' ');
  }
}

/// Result of a completed Apple sign-in.
@immutable
class AppleSignInResult {
  const AppleSignInResult({required this.user, required this.name});

  final User? user;
  final AppleName name;
}

/// Authentication against Supabase plus the native Google and Apple SDKs.
///
/// Every method throws an [AppFailure] on error. A user cancelling a social
/// sign-in is not an error: those methods return null/false.
abstract interface class AuthService {
  User? get currentUser;
  Session? get currentSession;

  /// Supabase auth events. Replays the events emitted so far (starting with
  /// `initialSession`) to each new listener.
  Stream<AuthState> get authStateChanges;

  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String displayName,
  });

  Future<void> signIn({required String email, required String password});

  /// Resends the sign-up confirmation email (works without a session).
  Future<void> resendSignupConfirmation(String email);

  /// Confirms the sign-up with the 6-digit code from the email and signs in.
  Future<void> verifySignupCode({required String email, required String code});

  /// Emails a 6-digit password reset code.
  Future<void> sendPasswordResetCode(String email);

  /// Exchanges a reset code for a recovery session. Returns the session's
  /// access token so the caller can recognise its own recovery event.
  Future<String?> verifyRecoveryCode({
    required String email,
    required String code,
  });

  Future<void> updatePassword(String newPassword);

  /// Re-reads the signed-in user from the server, or returns null when
  /// there is no session.
  Future<User?> reloadUser();

  /// Returns false when the user cancelled.
  Future<bool> signInWithGoogle();

  /// Returns null when the user cancelled.
  Future<AppleSignInResult?> signInWithApple();

  /// Stores [fullName] in the auth user's metadata.
  Future<void> updateFullName(String fullName);

  /// A fresh Sign in with Apple authorization code, so the server can
  /// revoke the user's Apple token when the account is deleted. Null when
  /// the user has no Apple identity or this device cannot ask Apple.
  /// Throws `apple_reauth_cancelled` when the user cancels.
  Future<String?> appleAuthorizationCode();

  /// Ends the local session (and the Google account selection). Never
  /// throws: the local session is always removed.
  Future<void> signOut();
}

final authServiceProvider = Provider<AuthService>(
  (ref) => SupabaseAuthService(ref.watch(supabaseClientProvider).auth),
);

class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._auth, [this._config = AppConfig.environment]);

  final GoTrueClient _auth;
  final AppConfig _config;

  static const List<String> _googleScopes = ['email', 'profile'];
  Future<void>? _googleInit;

  /// Raw nonce whose SHA-256 was given to Google at initialization (which
  /// happens once per process), so every ID token Google issues carries it
  /// and Supabase can check the token was issued for this app instance.
  String? _googleRawNonce;

  @override
  User? get currentUser => _auth.currentUser;

  @override
  Session? get currentSession => _auth.currentSession;

  @override
  Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  static String _normalise(String email) => email.trim().toLowerCase();

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String displayName,
  }) => ErrorMapper.guard(() async {
    final response = await _auth.signUp(
      email: _normalise(email),
      password: password,
      emailRedirectTo: AppConfig.authCallbackUrl,
      data: {'full_name': displayName.trim()},
    );
    if (response.session != null) return SignUpOutcome.signedIn;
    final identities = response.user?.identities;
    if (response.user != null && identities != null && identities.isEmpty) {
      return SignUpOutcome.alreadyRegistered;
    }
    return SignUpOutcome.confirmationSent;
  });

  @override
  Future<void> signIn({required String email, required String password}) =>
      ErrorMapper.guard(
        () => _auth.signInWithPassword(
          email: _normalise(email),
          password: password,
        ),
      );

  @override
  Future<void> resendSignupConfirmation(String email) => ErrorMapper.guard(
    () => _auth.resend(
      type: OtpType.signup,
      email: _normalise(email),
      emailRedirectTo: AppConfig.authCallbackUrl,
    ),
  );

  @override
  Future<void> verifySignupCode({
    required String email,
    required String code,
  }) => ErrorMapper.guard(
    () => _auth.verifyOTP(
      type: OtpType.signup,
      email: _normalise(email),
      token: code.trim(),
    ),
  );

  @override
  Future<void> sendPasswordResetCode(String email) => ErrorMapper.guard(
    () => _auth.resetPasswordForEmail(
      _normalise(email),
      redirectTo: AppConfig.authCallbackUrl,
    ),
  );

  @override
  Future<String?> verifyRecoveryCode({
    required String email,
    required String code,
  }) => ErrorMapper.guard(() async {
    final response = await _auth.verifyOTP(
      type: OtpType.recovery,
      email: _normalise(email),
      token: code.trim(),
    );
    return response.session?.accessToken;
  });

  @override
  Future<void> updatePassword(String newPassword) => ErrorMapper.guard(
    () => _auth.updateUser(UserAttributes(password: newPassword)),
  );

  @override
  Future<User?> reloadUser() => ErrorMapper.guard(() async {
    if (_auth.currentSession == null) return null;
    final response = await _auth.refreshSession();
    return response.user ?? _auth.currentUser;
  });

  // ---------------------------------------------------------------------------
  // Google
  // ---------------------------------------------------------------------------

  Future<void> _ensureGoogleInitialized() {
    final existing = _googleInit;
    if (existing != null) return existing;
    final rawNonce = Nonce.generate();
    _googleRawNonce = rawNonce;
    return _googleInit = GoogleSignIn.instance
        .initialize(
          serverClientId: _config.googleWebClientId,
          clientId: _config.googleIosClientId.isEmpty
              ? null
              : _config.googleIosClientId,
          nonce: Nonce.sha256Hex(rawNonce),
        )
        .catchError((Object error, StackTrace stackTrace) {
          // Not cached, so the next attempt retries.
          _googleInit = null;
          _googleRawNonce = null;
          Error.throwWithStackTrace(error, stackTrace);
        });
  }

  @override
  Future<bool> signInWithGoogle() async {
    if (!_config.isGoogleSignInConfigured) {
      throw const AppFailure.business('google_unavailable');
    }
    try {
      await _ensureGoogleInitialized();
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: _googleScopes,
      );
      final idToken = account.authentication.idToken;
      if (idToken == null) throw const AppFailure.business('google_failed');
      // Supabase verifies both tokens when both are present.
      final client = account.authorizationClient;
      final authorization =
          await client.authorizationForScopes(_googleScopes) ??
          await client.authorizeScopes(_googleScopes);
      await ErrorMapper.guard(
        () => _auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          accessToken: authorization.accessToken,
          nonce: _googleRawNonce,
        ),
      );
      return true;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      AppLogger.warn('Google sign-in failed', e.code);
      throw const AppFailure.business('google_failed');
    }
  }

  // ---------------------------------------------------------------------------
  // Apple
  // ---------------------------------------------------------------------------

  @override
  Future<AppleSignInResult?> signInWithApple() async {
    final rawNonce = Nonce.generate();
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: Nonce.sha256Hex(rawNonce),
      );
      final idToken = credential.identityToken;
      if (idToken == null) throw const AppFailure.business('apple_failed');
      final response = await ErrorMapper.guard(
        () => _auth.signInWithIdToken(
          provider: OAuthProvider.apple,
          idToken: idToken,
          nonce: rawNonce,
        ),
      );
      return AppleSignInResult(
        user: response.user,
        name: AppleName(
          givenName: credential.givenName,
          familyName: credential.familyName,
        ),
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      AppLogger.warn('Apple sign-in failed', e.code);
      throw const AppFailure.business('apple_failed');
    } on SignInWithAppleNotSupportedException {
      throw const AppFailure.business('apple_failed');
    }
  }

  @override
  Future<String?> appleAuthorizationCode() async {
    final user = _auth.currentUser;
    if (user == null || !_hasAppleIdentity(user)) return null;
    final native =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    if (!native) return null;
    try {
      if (!await SignInWithApple.isAvailable()) return null;
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [],
      );
      return credential.authorizationCode;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const AppFailure.business('apple_reauth_cancelled');
      }
      AppLogger.warn('Apple re-authorization failed', e.code);
      throw const AppFailure.business('apple_failed');
    } on SignInWithAppleNotSupportedException {
      return null;
    }
  }

  static bool _hasAppleIdentity(User user) {
    if (user.identities?.any((i) => i.provider == 'apple') ?? false) {
      return true;
    }
    final providers = user.appMetadata['providers'];
    return providers is List && providers.contains('apple');
  }

  @override
  Future<void> updateFullName(String fullName) => ErrorMapper.guard(
    () => _auth.updateUser(UserAttributes(data: {'full_name': fullName})),
  );

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on Object catch (e) {
      // The local session is removed before the server call; a failed
      // server call only leaves the refresh token to expire.
      AppLogger.warn('Server sign-out failed', e.runtimeType);
    }
    if (_googleInit != null) {
      try {
        await GoogleSignIn.instance.signOut();
      } on Object catch (e) {
        AppLogger.warn('Google sign-out failed', e.runtimeType);
      }
    }
  }
}
