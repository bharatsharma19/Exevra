import 'package:expense_manager/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppLogger.redact', () {
    test('removes email addresses', () {
      final out = AppLogger.redact('lookup failed for jane.doe@mail.test');
      expect(out, isNot(contains('jane.doe')));
      expect(out, contains('<email>'));
    });

    test('removes phone numbers', () {
      final out = AppLogger.redact('otp sent to +91 98765 43210');
      expect(out, isNot(contains('98765')));
    });

    test('removes JWTs and bearer tokens', () {
      const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.c2lnbmF0dXJl';
      expect(AppLogger.redact('token $jwt'), isNot(contains(jwt)));
      expect(
        AppLogger.redact('Authorization: Bearer abc.def-123'),
        isNot(contains('abc.def-123')),
      );
    });

    test('removes query strings from URLs', () {
      final out = AppLogger.redact(
        'GET https://exevra.app/invite?token=tok_123&email=a@b.test failed',
      );
      expect(out, contains('https://exevra.app/invite'));
      expect(out, isNot(contains('tok_123')));
      expect(out, isNot(contains('a@b.test')));
    });

    test('removes sensitive key/value pairs', () {
      final out = AppLogger.redact('{"password": "hunter22", "ok": true}');
      expect(out, isNot(contains('hunter22')));
      expect(out, contains('"ok": true'));
    });

    test('keeps ordinary messages intact', () {
      expect(
        AppLogger.redact('SupabaseService: fetchGroup fallback'),
        'SupabaseService: fetchGroup fallback',
      );
    });
  });
}
