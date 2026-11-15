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
