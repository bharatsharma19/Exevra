import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Build-time configuration for the app.
///
/// Values come from `--dart-define-from-file=config/<env>.json` (see
/// `config/README.md`). The client only ever holds the Supabase URL and the
/// anon (publishable) key; every other secret lives server-side.
@immutable
class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    this.appLinkHost = defaultAppLinkHost,
    this.sentryDsn = '',
    this.googleWebClientId = '',
    this.googleIosClientId = '',
  });

  static const String defaultAppLinkHost = 'exevra.app';

  /// Deployment environment reported with crash reports (`APP_ENV`).
  static const String appEnvironment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'production',
  );

  /// The configuration compiled into this build.
  static const AppConfig environment = AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
    appLinkHost: String.fromEnvironment(
      'APP_LINK_HOST',
      defaultValue: defaultAppLinkHost,
    ),
    sentryDsn: String.fromEnvironment('SENTRY_DSN'),
    googleWebClientId: String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
    googleIosClientId: String.fromEnvironment('GOOGLE_IOS_CLIENT_ID'),
  );

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String appLinkHost;
  final String sentryDsn;
  final String googleWebClientId;
  final String googleIosClientId;

  /// Problems with this configuration for the current build mode.
  List<String> get problems => validate(
    supabaseUrl: supabaseUrl,
    supabaseAnonKey: supabaseAnonKey,
    appLinkHost: appLinkHost,
    isRelease: kReleaseMode,
  );

  bool get isValid => problems.isEmpty;

  bool get isGoogleSignInConfigured => googleWebClientId.trim().isNotEmpty;

  /// Where Supabase sends the user back after an email link (sign-up
  /// confirmation, password recovery). Registered on both platforms and in
  /// the Supabase redirect allow-list; supabase_flutter handles it.
  static const String authCallbackUrl = 'com.exevra.app://auth-callback';

  /// Custom-scheme fallback for invite links (`exevra://invite/<token>`).
  static const String inviteScheme = 'exevra';

  /// Builds the public link for a group invitation token.
  Uri inviteLink(String token) =>
      Uri(scheme: 'https', host: appLinkHost, pathSegments: ['invite', token]);

  /// The published Terms of Service.
  Uri get termsUrl => Uri(scheme: 'https', host: appLinkHost, path: '/terms');

  /// The published Privacy Policy.
  Uri get privacyUrl =>
      Uri(scheme: 'https', host: appLinkHost, path: '/privacy');

  /// Markers that show a value was copied from an example and never filled.
  static const List<String> placeholderMarkers = [
    'your-project',
    'xyzcompany',
    'your_',
    'placeholder',
    'example',
    'changeme',
  ];

  /// Hosts that may use plain http, and only outside release builds.
  static const Set<String> localDevelopmentHosts = {
    '127.0.0.1',
    'localhost',
    '10.0.2.2',
  };

  static final RegExp _jwtShape = RegExp(
    r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$',
  );
  static final RegExp _publishableShape = RegExp(
    r'^sb_publishable_[A-Za-z0-9_-]{10,}$',
  );
  static final RegExp _hostShape = RegExp(
    r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$',
  );

  /// Pure validator: returns human-readable problems, empty when valid.
  ///
  /// Problem strings never contain the configured values themselves.
  static List<String> validate({
    required String supabaseUrl,
    required String supabaseAnonKey,
    String appLinkHost = defaultAppLinkHost,
    required bool isRelease,
  }) {
    final problems = <String>[];
    final url = supabaseUrl.trim();
    final key = supabaseAnonKey.trim();
    final host = appLinkHost.trim();

    if (url.isEmpty) {
      problems.add('SUPABASE_URL is missing.');
    } else if (_hasPlaceholder(url)) {
      problems.add('SUPABASE_URL still contains a placeholder value.');
    } else {
      final uri = Uri.tryParse(url);
      if (uri == null || uri.host.isEmpty || !uri.hasScheme) {
        problems.add('SUPABASE_URL is not a valid URL.');
      } else if (uri.scheme == 'https') {
        // Accepted.
      } else if (uri.scheme == 'http' &&
          !isRelease &&
          localDevelopmentHosts.contains(uri.host)) {
        // Local Supabase stack during development.
      } else if (uri.scheme == 'http' &&
          localDevelopmentHosts.contains(uri.host)) {
        problems.add('SUPABASE_URL must use https in release builds.');
      } else {
        problems.add('SUPABASE_URL must use https.');
      }
    }

    if (key.isEmpty) {
      problems.add('SUPABASE_ANON_KEY is missing.');
    } else if (_hasPlaceholder(key)) {
      problems.add('SUPABASE_ANON_KEY still contains a placeholder value.');
    } else if (key.startsWith('sb_secret_')) {
      problems.add(
        'SUPABASE_ANON_KEY is a secret key; use the anon (publishable) key.',
      );
    } else if (_publishableShape.hasMatch(key)) {
      // Accepted: new-style publishable key.
    } else if (_jwtShape.hasMatch(key)) {
      final role = _jwtRole(key);
      if (role == null) {
        problems.add('SUPABASE_ANON_KEY is not a valid Supabase key.');
      } else if (role != 'anon') {
        problems.add(
          'SUPABASE_ANON_KEY must be the anon (publishable) key, '
          'not a "$role" key.',
        );
      }
    } else {
      problems.add('SUPABASE_ANON_KEY is not a valid Supabase key.');
    }

    if (host.isEmpty) {
      problems.add('APP_LINK_HOST is missing.');
    } else if (_hasPlaceholder(host) || !_hostShape.hasMatch(host)) {
      problems.add('APP_LINK_HOST must be a plain host name.');
    }

    return problems;
  }

  static bool _hasPlaceholder(String value) {
    final lower = value.toLowerCase();
    return placeholderMarkers.any(lower.contains);
  }

  /// Returns the `role` claim of a JWT, or null when it cannot be decoded.
  static String? _jwtRole(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final header = _decodeSegment(parts[0]);
      final payload = _decodeSegment(parts[1]);
      if (header == null || payload == null) return null;
      final role = payload['role'];
      return role is String ? role : null;
    } on FormatException {
      return null;
    }
  }

  static Map<String, Object?>? _decodeSegment(String segment) {
    final decoded = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(segment))),
    );
    return decoded is Map<String, Object?> ? decoded : null;
  }
}
