import 'dart:convert';

import 'package:expense_manager/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

String _segment(Map<String, Object?> json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

/// Builds an unsigned JWT-shaped test value with the given role claim.
String _jwtWithRole(String role) =>
    '${_segment({'alg': 'HS256', 'typ': 'JWT'})}'
    '.${_segment({'iss': 'supabase', 'ref': 'abcdefghij', 'role': role})}'
    '.signature_part';

void main() {
  const validUrl = 'https://abcdefghijklmnop.supabase.co';
  final anonJwt = _jwtWithRole('anon');
  const publishableKey = 'sb_publishable_AbCdEf123456_test';

  List<String> validate({
    String url = validUrl,
    String? key,
    String host = 'exevra.app',
    bool isRelease = true,
  }) => AppConfig.validate(
    supabaseUrl: url,
    supabaseAnonKey: key ?? anonJwt,
    appLinkHost: host,
    isRelease: isRelease,
  );

  group('AppConfig.validate', () {
    test('accepts an https URL with an anon JWT', () {
      expect(validate(), isEmpty);
    });

    test('accepts a publishable key', () {
      expect(validate(key: publishableKey), isEmpty);
    });

    test('reports missing values', () {
      final problems = validate(url: '', key: '', host: '');
      expect(problems, contains('SUPABASE_URL is missing.'));
      expect(problems, contains('SUPABASE_ANON_KEY is missing.'));
      expect(problems, contains('APP_LINK_HOST is missing.'));
    });

    test('treats whitespace-only values as missing', () {
      expect(validate(url: '   '), contains('SUPABASE_URL is missing.'));
    });

    for (final placeholder in [
      'https://YOUR-PROJECT.supabase.co',
      'https://xyzcompany.supabase.co',
      'https://your_project.supabase.co',
      'https://placeholder.supabase.co',
      'https://Example.supabase.co',
      'https://CHANGEME.supabase.co',
    ]) {
      test('rejects placeholder URL $placeholder', () {
        expect(
          validate(url: placeholder),
          contains('SUPABASE_URL still contains a placeholder value.'),
        );
      });
    }

    test('rejects placeholder keys case-insensitively', () {
      for (final key in ['YOUR_ANON_KEY', 'placeholder', 'ChangeMe']) {
        expect(
          validate(key: key),
          contains('SUPABASE_ANON_KEY still contains a placeholder value.'),
          reason: key,
        );
      }
    });

    test('rejects the example config file values', () {
      final problems = validate(
        url: 'https://YOUR-PROJECT.supabase.co',
        key: 'YOUR_ANON_KEY',
      );
      expect(problems, hasLength(2));
    });

    test('rejects non-https URLs', () {
      expect(
        validate(url: 'http://abcdefghij.supabase.co', isRelease: false),
        contains('SUPABASE_URL must use https.'),
      );
      expect(
        validate(url: 'ftp://abcdefghij.supabase.co'),
        contains('SUPABASE_URL must use https.'),
      );
    });

    test('rejects malformed URLs', () {
      expect(
        validate(url: 'not a url'),
        contains('SUPABASE_URL is not a valid URL.'),
      );
    });

    group('local http hosts', () {
      for (final host in ['127.0.0.1', 'localhost', '10.0.2.2']) {
        test('$host is allowed in debug builds', () {
          expect(
            validate(url: 'http://$host:54321', isRelease: false),
            isEmpty,
          );
        });

        test('$host is rejected in release builds', () {
          expect(
            validate(url: 'http://$host:54321', isRelease: true),
            contains('SUPABASE_URL must use https in release builds.'),
          );
        });
      }
    });

    test('rejects keys that are not JWT or publishable shaped', () {
      for (final key in ['abc', 'a.b', 'sb_publishable_short', 'a.b.c.d']) {
        expect(
          validate(key: key),
          contains('SUPABASE_ANON_KEY is not a valid Supabase key.'),
          reason: key,
        );
      }
    });

    test('rejects a JWT-shaped key whose payload is not JSON', () {
      expect(
        validate(key: 'eyJhbGciOiJIUzI1NiJ9.e30.sig'),
        contains('SUPABASE_ANON_KEY is not a valid Supabase key.'),
      );
    });

    test('rejects server-side keys', () {
      expect(
        validate(key: _jwtWithRole('service_role')),
        contains(
          'SUPABASE_ANON_KEY must be the anon (publishable) key, '
          'not a "service_role" key.',
        ),
      );
      expect(
        validate(key: 'sb_secret_AbCdEf1234567890'),
        contains(
          'SUPABASE_ANON_KEY is a secret key; use the anon (publishable) key.',
        ),
      );
    });

    test('rejects an app link host with a scheme or path', () {
      for (final host in [
        'https://exevra.app',
        'exevra.app/invite',
        'exevra',
      ]) {
        expect(
          validate(host: host),
          contains('APP_LINK_HOST must be a plain host name.'),
          reason: host,
        );
      }
    });

    test('problem messages never echo the configured values', () {
      final problems = validate(
        url: 'http://secret-host.supabase.co',
        key: 'sb_secret_AbCdEf1234567890',
      );
      for (final problem in problems) {
        expect(problem, isNot(contains('secret-host')));
        expect(problem, isNot(contains('AbCdEf')));
      }
    });
  });

  group('AppConfig', () {
    test('builds invite links on the configured host', () {
      const config = AppConfig(
        supabaseUrl: validUrl,
        supabaseAnonKey: publishableKey,
      );
      expect(
        config.inviteLink('tok_123').toString(),
        'https://exevra.app/invite/tok_123',
      );
      expect(config.termsUrl.toString(), 'https://exevra.app/terms');
      expect(config.privacyUrl.toString(), 'https://exevra.app/privacy');
    });

    test('Google sign-in is unavailable without a web client id', () {
      const config = AppConfig(
        supabaseUrl: validUrl,
        supabaseAnonKey: publishableKey,
      );
      expect(config.isGoogleSignInConfigured, isFalse);
    });
  });
}
