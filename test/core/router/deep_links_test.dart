import 'dart:async';

import 'package:expense_manager/core/router/deep_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const host = 'exevra.app';
  const token = 'Abc_DEF-123456789012345678901234567890abcde';

  DeepLink? parse(String link) =>
      DeepLinks.parse(Uri.parse(link), appLinkHost: host);

  group('invite links', () {
    test('https path form', () {
      expect(
        parse('https://exevra.app/invite/$token'),
        const InviteLink(token),
      );
      expect(
        parse('https://www.exevra.app/invite/$token'),
        const InviteLink(token),
      );
      expect(
        parse('https://EXEVRA.app/invite/$token/'),
        const InviteLink(token),
      );
    });

    test('custom scheme form', () {
      expect(parse('exevra://invite/$token'), const InviteLink(token));
    });

    test('legacy ?token= forms', () {
      expect(
        parse('https://exevra.app/invite?token=$token'),
        const InviteLink(token),
      );
      expect(parse('exevra://invite?token=$token'), const InviteLink(token));
    });

    test('rejects other hosts, paths and malformed tokens', () {
      for (final link in [
        'https://evil.example/invite/$token',
        'http://exevra.app/invite/$token',
        'https://exevra.app/other/$token',
        'https://exevra.app/invite',
        'https://exevra.app/invite/short',
        'https://exevra.app/invite/$token/extra',
        'https://exevra.app/invite/bad%20token%20with%20spaces%20xx',
        'exevra://other/$token',
        'exevra://invite',
        'mailto:someone@example.com',
      ]) {
        expect(parse(link), isNull, reason: link);
      }
    });
  });

  test('the auth callback is left to supabase_flutter', () {
    expect(
      parse('com.exevra.app://auth-callback?code=abc'),
      isA<AuthCallbackLink>(),
    );
    expect(
      parse('com.exevra.app://auth-callback#access_token=x'),
      isA<AuthCallbackLink>(),
    );
  });

  group('session callbacks', () {
    bool accepts(String link) =>
        DeepLinks.isSessionCallback(Uri.parse(link), appLinkHost: host);

    test('a PKCE code or an error is exchanged', () {
      expect(accepts('com.exevra.app://auth-callback?code=abc'), isTrue);
      expect(accepts('com.exevra.app://auth-callback/?code=abc'), isTrue);
      expect(
        accepts(
          'com.exevra.app://auth-callback?error=access_denied'
          '&error_code=otp_expired&error_description=Link+expired',
        ),
        isTrue,
      );
      expect(
        accepts('com.exevra.app://auth-callback#error=access_denied'),
        isTrue,
      );
    });

    test('links that carry tokens are never exchanged', () {
      for (final link in [
        'com.exevra.app://auth-callback#access_token=a&refresh_token=r'
            '&expires_in=3600&token_type=bearer',
        'com.exevra.app://auth-callback#access_token=a&refresh_token=r'
            '&expires_in=3600&token_type=bearer&type=recovery',
        'com.exevra.app://auth-callback?access_token=a&refresh_token=r'
            '&expires_in=3600&token_type=bearer',
        'com.exevra.app://auth-callback?code=abc#access_token=a'
            '&refresh_token=r',
        'com.exevra.app://auth-callback?code=abc&refresh_token=r',
        'com.exevra.app://auth-callback#provider_token=p&code=abc',
      ]) {
        expect(accepts(link), isFalse, reason: link);
      }
    });

    test('anything but the auth callback is left alone', () {
      for (final link in [
        'com.exevra.app://auth-callback',
        'com.exevra.app://other?code=abc',
        'exevra://invite/$token?code=abc',
        'https://exevra.app/invite/$token?code=abc',
        'https://evil.example/auth-callback?code=abc',
      ]) {
        expect(accepts(link), isFalse, reason: link);
      }
    });
  });

  test('the listener passes each link once', () async {
    final source = _Source(Uri.parse('exevra://invite/$token'));
    final seen = <DeepLink>[];
    final listener = DeepLinkListener(
      source: source,
      onLink: seen.add,
      appLinkHost: host,
    );
    addTearDown(listener.dispose);
    await Future<void>.delayed(Duration.zero);
    // app_links may deliver the initial link on the stream too.
    source.controller.add(Uri.parse('exevra://invite/$token'));
    source.controller.add(Uri.parse('https://elsewhere.example/'));
    await Future<void>.delayed(Duration.zero);
    expect(seen, [const InviteLink(token)]);
    await source.close();
  });

  test('the same link opened again later is handled again', () async {
    final source = _Source(null);
    var now = DateTime.utc(2026, 11, 15, 12);
    final seen = <DeepLink>[];
    final listener = DeepLinkListener(
      source: source,
      onLink: seen.add,
      appLinkHost: host,
      clock: () => now,
    );
    addTearDown(listener.dispose);
    final link = Uri.parse('exevra://invite/$token');

    source.controller.add(link);
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(minutes: 1));
    source.controller.add(link);
    await Future<void>.delayed(Duration.zero);

    expect(seen, [const InviteLink(token), const InviteLink(token)]);
    await source.close();
  });
}

class _Source implements LinkSource {
  _Source(this.initial);

  final Uri? initial;
  final controller = StreamController<Uri>.broadcast();

  @override
  Future<Uri?> initialLink() async => initial;

  @override
  Stream<Uri> get links => controller.stream;

  Future<void> close() => controller.close();
}
