import 'package:expense_manager/core/observability/crash_reporting.dart';
import 'package:expense_manager/core/observability/pii_scrubber.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

const _jwt =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.'
    'SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';

void main() {
  group('PiiScrubber.scrubText', () {
    test('removes emails, JWTs, keys and bearer tokens', () {
      final out = PiiScrubber.scrubText(
        'user asha.k+test@example.co.in failed with token $_jwt, '
        'key sb_secret_abcDEF123_xyz and sk-ant-api03-ABCDEFGHIJKL, '
        'header Authorization: Bearer abc.def-ghi',
      );
      expect(out, isNot(contains('asha')));
      expect(out, isNot(contains('example.co.in')));
      expect(out, isNot(contains('eyJ')));
      expect(out, isNot(contains('sb_secret')));
      expect(out, isNot(contains('sk-ant')));
      expect(out, isNot(contains('abc.def-ghi')));
      expect(out, contains('[email]'));
      expect(out, contains('[jwt]'));
      expect(out, contains('[key]'));
    });

    test('strips query strings and fragments from URLs', () {
      expect(
        PiiScrubber.scrubText(
          'GET https://x.supabase.co/rest/v1/expenses?select=*&apikey=k '
          'then com.exevra.app://auth-callback?code=abc#frag done',
        ),
        'GET https://x.supabase.co/rest/v1/expenses '
        'then com.exevra.app://auth-callback done',
      );
    });

    test('removes international phone numbers and key=value secrets', () {
      final out = PiiScrubber.scrubText(
        'call +91 98765 43210, password=hunter2 "refresh_token": "r1"',
      );
      expect(out, isNot(contains('98765')));
      expect(out, isNot(contains('hunter2')));
      expect(out, isNot(contains('"r1"')));
    });

    test('keeps ordinary text, amounts and stack locations', () {
      const text =
          'Failed to add expense of 1250.50 INR at lib/a.dart:120:7 (2 tries)';
      expect(PiiScrubber.scrubText(text), text);
    });
  });

  group('PiiScrubber.isSensitiveKey', () {
    for (final key in [
      'email',
      'userEmail',
      'access_token',
      'refreshToken',
      'Authorization',
      'cookie',
      'password',
      'api_key',
      'apiKey',
      'ip_address',
      'phone_number',
      'username',
      'http.query',
    ]) {
      test('flags $key', () => expect(PiiScrubber.isSensitiveKey(key), isTrue));
    }

    for (final key in ['state', 'route', 'url', 'status_code', 'spinner']) {
      test(
        'keeps $key',
        () => expect(PiiScrubber.isSensitiveKey(key), isFalse),
      );
    }
  });

  group('PiiScrubber.scrubEvent', () {
    SentryEvent buildEvent() {
      final event = SentryEvent(
        message: SentryMessage(
          'Sign-in failed for asha@example.com',
          template: 'Sign-in failed for %s',
          params: ['asha@example.com'],
        ),
        exceptions: [
          SentryException(
            type: 'AuthException',
            value: 'Invalid token $_jwt for asha@example.com',
          ),
        ],
        user: SentryUser(
          id: 'user-123',
          email: 'asha@example.com',
          username: 'asha',
          ipAddress: '203.0.113.7',
          name: 'Asha K',
          data: {'plan': 'free'},
        ),
        request: SentryRequest(
          url: 'https://x.supabase.co/auth/v1/token?grant_type=password',
          method: 'POST',
          queryString: 'grant_type=password',
          cookies: 'sb-access-token=abc',
          headers: {'Authorization': 'Bearer abc'},
          data: {'email': 'asha@example.com', 'password': 'pw'},
          fragment: 'frag',
        ),
        tags: {'screen': 'login', 'user_email': 'asha@example.com'},
        transaction: '/invite?token=abc',
        breadcrumbs: [
          Breadcrumb.http(
            url: Uri.parse('https://x.supabase.co/rest/v1/groups?id=eq.1'),
            method: 'GET',
          ),
        ],
      );
      // ignore: deprecated_member_use
      event.extra = {
        'note': 'mail asha@example.com',
        'session': 'secret-session',
        'nested': {
          'access_token': 'abc',
          'list': ['sk-ant-abcdefghijkl'],
        },
      };
      event.contexts['custom'] = {
        'email': 'asha@example.com',
        'detail': 'Bearer abc.def',
      };
      event.contexts['auth'] = {'state': 'signedIn'};
      event.contexts.device = SentryDevice(name: "Asha's phone", model: 'P8');
      return event;
    }

    test('keeps only the user id', () {
      final event = PiiScrubber.scrubEvent(buildEvent(), Hint());
      expect(event.user?.id, 'user-123');
      expect(event.user?.email, isNull);
      expect(event.user?.username, isNull);
      expect(event.user?.ipAddress, isNull);
      expect(event.user?.name, isNull);
      expect(event.user?.data, isNull);
    });

    test('drops a user without an id', () {
      final event = buildEvent()..user = SentryUser(email: 'a@b.co');
      expect(PiiScrubber.scrubEvent(event, Hint()).user, isNull);
    });

    test('reduces the request to method and URL without the query', () {
      final request = PiiScrubber.scrubEvent(buildEvent(), Hint()).request!;
      expect(request.url, 'https://x.supabase.co/auth/v1/token');
      expect(request.method, 'POST');
      expect(request.queryString, isNull);
      expect(request.cookies, isNull);
      expect(request.headers, isEmpty);
      expect(request.data, isNull);
      expect(request.fragment, isNull);
    });

    test('scrubs messages, exceptions, tags and the transaction', () {
      final event = PiiScrubber.scrubEvent(buildEvent(), Hint());
      expect(event.message?.formatted, 'Sign-in failed for [email]');
      expect(event.message?.params, ['[email]']);
      expect(event.exceptions!.single.value, 'Invalid token [jwt] for [email]');
      expect(event.tags, {'screen': 'login'});
      expect(event.transaction, '/invite');
    });

    test('scrubs extra data and contexts recursively', () {
      final event = PiiScrubber.scrubEvent(buildEvent(), Hint());
      // ignore: deprecated_member_use
      expect(event.extra, {
        'note': 'mail [email]',
        'nested': {
          'list': ['[key]'],
        },
      });
      expect(event.contexts['custom'], {'detail': 'Bearer [token]'});
      expect(event.contexts.containsKey('auth'), isFalse);
      expect(event.contexts.device?.name, isNull);
      expect(event.contexts.device?.model, 'P8');
    });

    test('scrubs breadcrumbs attached to the event', () {
      final event = PiiScrubber.scrubEvent(buildEvent(), Hint());
      final data = event.breadcrumbs!.single.data!;
      expect(data['url'], 'https://x.supabase.co/rest/v1/groups');
      expect(data.containsKey('http.query'), isFalse);
      expect(data.values.join(' '), isNot(contains('eq.1')));
    });
  });

  group('PiiScrubber.scrubBreadcrumb', () {
    test('scrubs the message and data', () {
      final crumb = PiiScrubber.scrubBreadcrumb(
        Breadcrumb(
          message: 'Opened com.exevra.app://auth-callback?code=secret',
          data: {'to': '/invite?token=abc', 'email': 'a@b.co', 'count': 2},
        ),
        Hint(),
      )!;
      expect(crumb.message, 'Opened com.exevra.app://auth-callback');
      expect(crumb.data, {'to': '/invite', 'count': 2});
    });

    test('passes null through', () {
      expect(PiiScrubber.scrubBreadcrumb(null, Hint()), isNull);
    });
  });

  group('configureSentry', () {
    test('applies the privacy settings', () {
      final options = SentryFlutterOptions();
      configureSentry(options, 'https://k@o1.ingest.sentry.io/1', 'r@1+1');
      expect(options.dsn, 'https://k@o1.ingest.sentry.io/1');
      expect(options.sendDefaultPii, isFalse);
      expect(options.tracesSampleRate, isNull);
      expect(options.isTracingEnabled(), isFalse);
      expect(options.attachScreenshot, isFalse);
      expect(options.attachViewHierarchy, isFalse);
      expect(options.environment, 'production');
      expect(options.release, 'r@1+1');
      expect(options.beforeSend, isNotNull);
      expect(options.beforeBreadcrumb, isNotNull);
    });
  });

  group('runAppGuarded without a DSN', () {
    test('installs logging handlers and runs the app', () async {
      final previousFlutter = FlutterError.onError;
      final previousPlatform = PlatformDispatcher.instance.onError;
      addTearDown(() {
        FlutterError.onError = previousFlutter;
        PlatformDispatcher.instance.onError = previousPlatform;
      });

      var ran = false;
      await runAppGuarded(() => ran = true);

      expect(ran, isTrue);
      expect(isCrashReportingConfigured, isFalse);
      expect(FlutterError.onError, isNot(same(previousFlutter)));
      expect(
        PlatformDispatcher.instance.onError!(StateError('x'), StackTrace.empty),
        isTrue,
      );
      expect(
        () => FlutterError.onError!(
          FlutterErrorDetails(exception: StateError('y')),
        ),
        returnsNormally,
      );
    });
  });
}
