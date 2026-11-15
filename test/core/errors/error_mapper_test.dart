import 'dart:async';
import 'dart:io';

import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/errors/failure_messages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

PostgrestException pg(String code, [String message = 'x y z']) =>
    PostgrestException(message: message, code: code);

void main() {
  group('PostgrestException', () {
    final cases = <(PostgrestException, AppFailure)>[
      (
        pg('42501', 'not_group_admin'),
        const AppFailure.permissionDenied(key: 'not_group_admin'),
      ),
      (
        pg('42501', 'permission denied for table groups'),
        const AppFailure.permissionDenied(),
      ),
      (pg('42501', 'not_authenticated'), const AppFailure.sessionExpired()),
      (
        pg('42501', 'email_not_confirmed'),
        const AppFailure.emailNotConfirmed(),
      ),
      (pg('42501', 'banned'), const AppFailure.business('banned')),
      (
        pg('42501', 'invite_email_mismatch'),
        const AppFailure.business('invite_email_mismatch'),
      ),
      (pg('PGRST116'), const AppFailure.notFound()),
      (pg('PGRST301'), const AppFailure.sessionExpired()),
      (pg('PGRST303'), const AppFailure.sessionExpired()),
      (
        pg('23505', 'already_member'),
        const AppFailure.conflict(key: 'already_member'),
      ),
      (
        pg('23505', 'duplicate key value violates unique constraint'),
        const AppFailure.conflict(),
      ),
      (
        pg('23514', 'new row violates check constraint'),
        const AppFailure.validation(),
      ),
      (
        pg('22P02', 'invalid input syntax for type uuid'),
        const AppFailure.validation(),
      ),
      (
        pg('22023', 'invalid_currency'),
        const AppFailure.validation(key: 'invalid_currency'),
      ),
      (
        pg('P0001', 'invite_expired'),
        const AppFailure.business('invite_expired'),
      ),
      (
        pg('P0001', 'settlement_exceeds_debt'),
        const AppFailure.business('settlement_exceeds_debt'),
      ),
      (pg('P0001', 'rate_limited'), const AppFailure.rateLimited()),
      (pg('P0001', 'quota_exceeded'), const AppFailure.quotaExceeded()),
      (
        pg('P0002', 'group_not_found'),
        const AppFailure.notFound(key: 'group_not_found'),
      ),
      (pg('57014'), const AppFailure.timeout()),
      (pg('429'), const AppFailure.rateLimited()),
      (pg('503'), const AppFailure.network()),
      (pg('XX000', 'boom'), const AppFailure.unknown()),
    ];
    for (final (input, expected) in cases) {
      test('${input.code} ${input.message} -> $expected', () {
        expect(ErrorMapper.map(input), expected);
      });
    }
  });

  group('AuthException', () {
    final cases = <(AuthException, AppFailure)>[
      (
        const AuthApiException('x', code: 'invalid_credentials'),
        const AppFailure.invalidCredentials(),
      ),
      (
        const AuthApiException('x', code: 'email_not_confirmed'),
        const AppFailure.emailNotConfirmed(),
      ),
      (
        const AuthApiException('x', code: 'user_already_exists'),
        const AppFailure.accountExists(),
      ),
      (
        const AuthApiException('x', code: 'weak_password'),
        const AppFailure.weakPassword(),
      ),
      (
        const AuthApiException('x', code: 'over_email_send_rate_limit'),
        const AppFailure.rateLimited(),
      ),
      (
        const AuthApiException('x', code: 'over_request_rate_limit'),
        const AppFailure.rateLimited(),
      ),
      (
        const AuthApiException('x', code: 'otp_expired'),
        const AppFailure.codeExpired(),
      ),
      (
        const AuthApiException('x', code: 'same_password'),
        const AppFailure.validation(field: 'password', key: 'same_password'),
      ),
      (
        const AuthApiException('x', code: 'session_expired'),
        const AppFailure.sessionExpired(),
      ),
      (
        const AuthApiException('x', code: 'refresh_token_not_found'),
        const AppFailure.sessionExpired(),
      ),
      (AuthSessionMissingException(), const AppFailure.sessionExpired()),
      (
        const AuthException('x', statusCode: '429'),
        const AppFailure.rateLimited(),
      ),
      (
        const AuthException('x', code: 'something_new'),
        const AppFailure.unknown(),
      ),
    ];
    for (final (input, expected) in cases) {
      test('${input.code ?? input.runtimeType} -> $expected', () {
        expect(ErrorMapper.map(input), expected);
      });
    }

    test('weak password keeps the reasons', () {
      final failure = ErrorMapper.map(
        AuthWeakPasswordException(
          message: 'weak',
          statusCode: '422',
          reasons: ['length'],
        ),
      );
      expect(failure, isA<WeakPasswordFailure>());
      expect((failure as WeakPasswordFailure).reasons, ['length']);
    });

    test('retryable fetch errors are network or offline', () {
      expect(
        ErrorMapper.map(
          AuthRetryableFetchException(message: 'Failed host lookup'),
        ),
        const AppFailure.offline(),
      );
      expect(
        ErrorMapper.map(
          AuthRetryableFetchException(message: 'Connection reset'),
        ),
        const AppFailure.network(),
      );
    });
  });

  group('FunctionException', () {
    FunctionException fx(int status, String code, [String? reason]) =>
        FunctionsHttpException(
          status: status,
          details: {
            'error': {'code': code, 'message': 'Friendly', 'reason': ?reason},
          },
        );

    final cases = <(FunctionException, AppFailure)>[
      (fx(401, 'unauthorized'), const AppFailure.sessionExpired()),
      (
        fx(403, 'forbidden', 'not_group_admin'),
        const AppFailure.permissionDenied(key: 'not_group_admin'),
      ),
      (
        fx(403, 'reauth_required'),
        const AppFailure.business('reauth_required'),
      ),
      (
        fx(403, 'consent_required'),
        const AppFailure.business('consent_required'),
      ),
      (
        fx(409, 'conflict', 'already_member'),
        const AppFailure.conflict(key: 'already_member'),
      ),
      (fx(413, 'too_long'), const AppFailure.validation(key: 'too_long')),
      (fx(429, 'rate_limited'), const AppFailure.rateLimited()),
      (fx(429, 'quota_exceeded'), const AppFailure.quotaExceeded()),
      (
        fx(500, 'deletion_failed'),
        const AppFailure.business('deletion_failed'),
      ),
      (fx(503, 'unavailable'), const AppFailure.business('unavailable')),
      (
        const FunctionsHttpException(status: 502, details: 'Bad gateway'),
        const AppFailure.business('unavailable'),
      ),
      (const FunctionsHttpException(status: 404), const AppFailure.notFound()),
    ];
    for (final (input, expected) in cases) {
      test('${input.status} ${input.details} -> $expected', () {
        expect(ErrorMapper.map(input), expected);
      });
    }

    test('a fetch failure maps its cause', () {
      expect(
        ErrorMapper.map(
          const FunctionsFetchException(
            details: SocketException('Failed host lookup: example.supabase.co'),
          ),
        ),
        const AppFailure.offline(),
      );
      expect(
        ErrorMapper.map(const FunctionsFetchException(details: 'oops')),
        const AppFailure.network(),
      );
    });
  });

  group('transport', () {
    test('socket errors', () {
      expect(
        ErrorMapper.map(const SocketException('Failed host lookup: x')),
        const AppFailure.offline(),
      );
      expect(
        ErrorMapper.map(const SocketException('Connection refused')),
        const AppFailure.network(),
      );
    });

    test('client, handshake and timeout errors', () {
      expect(
        ErrorMapper.map(http.ClientException('Connection closed')),
        const AppFailure.network(),
      );
      expect(
        ErrorMapper.map(const HandshakeException('bad cert')),
        const AppFailure.network(),
      );
      expect(
        ErrorMapper.map(TimeoutException('slow')),
        const AppFailure.timeout(),
      );
    });

    test('an AppFailure passes through unchanged', () {
      const failure = AppFailure.business('invite_expired');
      expect(ErrorMapper.map(failure), same(failure));
    });

    test('anything else is unknown', () {
      expect(ErrorMapper.map(StateError('x')), const AppFailure.unknown());
    });

    test('guard rethrows as AppFailure', () async {
      await expectLater(
        ErrorMapper.guard<void>(
          () async => throw pg('P0001', 'invite_expired'),
        ),
        throwsA(const AppFailure.business('invite_expired')),
      );
    });
  });

  group('friendlyMessage', () {
    test('uses the business key when known', () {
      expect(
        friendlyMessage(const AppFailure.business('settlement_exceeds_debt')),
        "That's more than you currently owe this person.",
      );
      expect(
        friendlyMessage(
          const AppFailure.permissionDenied(key: 'not_group_admin'),
        ),
        'Only the group admin can do that.',
      );
    });

    test('expense moves, locks and dates have their own copy', () {
      String forKey(String key) => friendlyMessageForKey(key);
      expect(
        forKey('expense_locked_member_left'),
        "This expense can't be changed because someone in it has left the "
        'group.',
      );
      expect(
        friendlyMessage(
          const AppFailure.business('settlement_locked_member_left'),
        ),
        contains('left the group'),
      );
      expect(
        friendlyMessage(
          const AppFailure.permissionDenied(key: 'payer_not_member'),
        ),
        contains('members can pay'),
      );
      expect(
        friendlyMessage(const AppFailure.validation(key: 'invalid_date')),
        contains('2000'),
      );
      expect(
        friendlyMessage(const AppFailure.validation(key: 'invalid_range')),
        contains('date range'),
      );
      expect(
        friendlyMessage(const AppFailure.validation(key: 'currency_mismatch')),
        contains("group's currency"),
      );
      expect(
        friendlyMessage(const AppFailure.notFound(key: 'expense_not_found')),
        contains("couldn't find that expense"),
      );
      expect(
        friendlyMessage(
          const AppFailure.permissionDenied(key: 'not_expense_payer'),
        ),
        'Only the person who paid can move this expense.',
      );
      expect(
        friendlyMessage(const AppFailure.validation(key: 'invalid_target')),
        'Choose another member.',
      );
      expect(
        forKey('expense_scope_unchanged'),
        'This expense is already there.',
      );
    });

    test('the expense and settlement keys map from Postgres errors', () {
      AppFailure map(String code, String message) =>
          ErrorMapper.map(PostgrestException(message: message, code: code));
      expect(
        map('P0001', 'expense_locked_member_left'),
        const AppFailure.business('expense_locked_member_left'),
      );
      expect(
        map('P0001', 'settlement_locked_member_left'),
        const AppFailure.business('settlement_locked_member_left'),
      );
      expect(
        map('42501', 'payer_not_member'),
        const AppFailure.permissionDenied(key: 'payer_not_member'),
      );
      expect(
        map('42501', 'not_expense_payer'),
        const AppFailure.permissionDenied(key: 'not_expense_payer'),
      );
      expect(
        map('P0002', 'expense_not_found'),
        const AppFailure.notFound(key: 'expense_not_found'),
      );
      for (final key in [
        'invalid_date',
        'invalid_range',
        'currency_mismatch',
        'invalid_target',
      ]) {
        expect(map('22023', key), AppFailure.validation(key: key));
      }
    });

    test('falls back to the failure type', () {
      expect(
        friendlyMessage(const AppFailure.business('brand_new_key')),
        "We couldn't complete that. Please try again.",
      );
      expect(
        friendlyMessage(const AppFailure.permissionDenied()),
        "You don't have permission to do that.",
      );
    });

    test('never echoes raw text', () {
      const failures = <AppFailure>[
        AppFailure.network(),
        AppFailure.offline(),
        AppFailure.timeout(),
        AppFailure.permissionDenied(),
        AppFailure.notFound(),
        AppFailure.validation(),
        AppFailure.conflict(),
        AppFailure.rateLimited(),
        AppFailure.quotaExceeded(),
        AppFailure.sessionExpired(),
        AppFailure.emailNotConfirmed(),
        AppFailure.invalidCredentials(),
        AppFailure.accountExists(),
        AppFailure.weakPassword(),
        AppFailure.codeExpired(),
        AppFailure.business('x'),
        AppFailure.unknown(),
      ];
      for (final failure in failures) {
        final message = friendlyMessage(failure);
        expect(message, isNotEmpty);
        expect(message, isNot(contains('Exception')));
        expect(message.length, lessThan(160));
      }
    });
  });
}
