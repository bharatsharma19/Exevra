import 'dart:convert';

import 'package:expense_manager/core/config/app_config.dart';
import 'package:expense_manager/core/security/nonce.dart';
import 'package:expense_manager/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Google Sign-In that records how it was initialised.
class _FakeGooglePlatform extends GoogleSignInPlatform {
  InitParameters? initParams;
  int signOuts = 0;

  @override
  Future<void> init(InitParameters params) async => initParams = params;

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) async => null;

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(
    AuthenticateParameters params,
  ) async => const AuthenticationResults(
    user: GoogleSignInUserData(email: 'a@example.com', id: 'g-1'),
    authenticationTokens: AuthenticationTokenData(idToken: 'google-id-token'),
  );

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async => const ClientAuthorizationTokenData(accessToken: 'google-access');

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async => null;

  @override
  Future<void> signOut(SignOutParams params) async {
    // Google Sign-In must be initialised before any other call.
    expect(initParams, isNotNull);
    signOuts++;
  }

  @override
  Future<void> disconnect(DisconnectParams params) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Google sign-in binds the ID token to a nonce', () async {
    final google = _FakeGooglePlatform();
    GoogleSignInPlatform.instance = google;
    Map<String, Object?>? tokenRequest;
    final client = MockClient((request) async {
      tokenRequest = jsonDecode(request.body) as Map<String, Object?>;
      return http.Response(
        jsonEncode({
          'access_token': 'jwt',
          'token_type': 'bearer',
          'expires_in': 3600,
          'refresh_token': 'refresh',
          'user': {
            'id': 'u-1',
            'aud': 'authenticated',
            'created_at': '2026-11-15T00:00:00Z',
            'app_metadata': <String, Object?>{},
            'user_metadata': <String, Object?>{},
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = SupabaseAuthService(
      GoTrueClient(
        url: 'https://project.supabase.example/auth/v1',
        httpClient: client,
        autoRefreshToken: false,
      ),
      const AppConfig(
        supabaseUrl: 'https://project.supabase.example',
        supabaseAnonKey: 'anon',
        googleWebClientId: 'web-client.apps.googleusercontent.com',
      ),
    );

    expect(await service.signInWithGoogle(), isTrue);

    final hashed = google.initParams?.nonce;
    final raw = tokenRequest?['nonce'];
    expect(hashed, isNotNull);
    expect(raw, isA<String>());
    expect(Nonce.sha256Hex(raw! as String), hashed);
    expect(tokenRequest?['id_token'], 'google-id-token');
  });

  test('signing out after a cold start also signs out of Google', () async {
    final google = _FakeGooglePlatform();
    GoogleSignInPlatform.instance = google;
    // A new service is a new app run: Google was not used in it yet.
    final service = SupabaseAuthService(
      GoTrueClient(
        url: 'https://project.supabase.example/auth/v1',
        httpClient: MockClient((_) async => http.Response('{}', 200)),
        autoRefreshToken: false,
      ),
      const AppConfig(
        supabaseUrl: 'https://project.supabase.example',
        supabaseAnonKey: 'anon',
        googleWebClientId: 'web-client.apps.googleusercontent.com',
      ),
    );

    await service.signOut();

    expect(google.initParams, isNotNull);
    expect(google.signOuts, 1);
  });
}
