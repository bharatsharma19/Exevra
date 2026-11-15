import 'dart:convert';

import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/data/repositories/account_repository.dart';
import 'package:expense_manager/data/repositories/expense_repository.dart';
import 'package:expense_manager/data/repositories/group_repository.dart';
import 'package:expense_manager/data/repositories/invitation_repository.dart';
import 'package:expense_manager/data/repositories/profile_repository.dart';
import 'package:expense_manager/data/repositories/settlement_repository.dart';
import 'package:expense_manager/models/expense.dart';
import 'package:expense_manager/models/group.dart';
import 'package:expense_manager/models/money.dart';
import 'package:expense_manager/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Records requests and answers with a canned response.
class FakeServer {
  final List<http.Request> requests = [];
  http.Response Function(http.Request request) respond = (_) =>
      http.Response('[]', 200);

  SupabaseClient client() => SupabaseClient(
    'https://unit.test',
    'sb_publishable_test',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      requests.add(request);
      final r = respond(request);
      return http.Response.bytes(
        r.bodyBytes,
        r.statusCode,
        headers: r.headers,
        request: request,
      );
    }),
  );

  http.Request get last => requests.last;
  Map<String, dynamic> get lastJsonBody =>
      jsonDecode(last.body) as Map<String, dynamic>;
}

http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

final expenseRow = {
  'id': 'e1',
  'user_id': 'u1',
  'group_id': null,
  'title': 'Lunch',
  'amount_minor': 125050,
  'currency': 'INR',
  'category': 'Food',
  'spent_at': '2026-11-15T17:00:00+00:00',
  'note': null,
  'receipt_url': null,
  'created_at': '2026-11-15T17:00:01+00:00',
  'updated_at': '2026-11-15T17:00:01+00:00',
};

void main() {
  late FakeServer server;
  setUp(() => server = FakeServer());

  group('ExpenseRepository', () {
    test(
      'first page orders by spent_at and id and asks for one extra',
      () async {
        server.respond = (_) => json([expenseRow]);
        final repo = SupabaseExpenseRepository(server.client());
        final page = await repo.fetchPage(
          userId: 'u1',
          query: const ExpenseQuery(scope: ExpenseScope.personal()),
          limit: 2,
        );
        expect(page.items, hasLength(1));
        expect(page.hasMore, isFalse);
        final q = server.last.url.queryParameters;
        expect(q['user_id'], 'eq.u1');
        expect(q['group_id'], 'is.null');
        expect(q['order'], 'spent_at.desc.nullslast,id.desc.nullslast');
        expect(q['limit'], '3');
      },
    );

    test('next page uses a keyset cursor and reports more', () async {
      server.respond = (_) => json([
        expenseRow,
        {...expenseRow, 'id': 'e0'},
      ]);
      final repo = SupabaseExpenseRepository(server.client());
      final page = await repo.fetchPage(
        userId: 'u1',
        query: const ExpenseQuery(
          scope: ExpenseScope.group('g1'),
          category: 'Food',
          search: '50%_off',
        ),
        after: ExpenseCursor(DateTime.utc(2026, 11, 16), 'e9'),
        limit: 1,
      );
      expect(page.items.single.id, 'e1');
      expect(page.next?.id, 'e1');
      final q = server.last.url.queryParameters;
      expect(q['group_id'], 'eq.g1');
      expect(q['category'], 'eq.Food');
      expect(q['title'], r'ilike.%50\%\_off%');
      expect(
        q['or'],
        '(spent_at.lt."2026-11-16T00:00:00.000Z",'
        'and(spent_at.eq."2026-11-16T00:00:00.000Z",id.lt."e9"))',
      );
    });

    test('personal and group timeline combines both filters', () async {
      server.respond = (_) => json([]);
      final repo = SupabaseExpenseRepository(server.client());
      await repo.fetchPage(
        userId: 'u1',
        query: const ExpenseQuery(scope: ExpenseScope.personalAndGroup('g1')),
        after: ExpenseCursor(DateTime.utc(2026, 11, 16), 'e9'),
      );
      final or = server.last.url.queryParameters['or']!;
      expect(or, startsWith('(and(or(and(user_id.eq."u1",group_id.is.null)'));
      expect(or, contains('group_id.eq."g1"'));
      expect(or, contains('spent_at.lt.'));
    });

    test('update with no rows is a failure, not a silent success', () async {
      server.respond = (_) => json([]);
      final repo = SupabaseExpenseRepository(server.client());
      final expense = Expense.fromJson(expenseRow);
      await expectLater(
        repo.update(expense.copyWith(note: null)),
        throwsA(const AppFailure.permissionDenied()),
      );
      final body = server.lastJsonBody;
      expect(body.containsKey('note'), isTrue);
      expect(body['note'], isNull);
      expect(body.containsKey('user_id'), isFalse);
      expect(server.last.method, 'PATCH');
    });

    test('delete with no rows is a failure', () async {
      server.respond = (_) => json([]);
      final repo = SupabaseExpenseRepository(server.client());
      await expectLater(
        repo.delete('e1'),
        throwsA(isA<PermissionDeniedFailure>()),
      );
    });

    test('server errors become AppFailure', () async {
      server.respond = (_) => json({
        'code': '42501',
        'message': 'new row violates row-level security policy',
      }, 403);
      final repo = SupabaseExpenseRepository(server.client());
      await expectLater(
        repo.create(
          'u1',
          ExpenseDraft(
            title: 'Taxi',
            amount: Money(100, 'INR'),
            category: 'Transport',
            spentAt: DateTime.utc(2026),
            groupId: 'g1',
          ),
        ),
        throwsA(isA<PermissionDeniedFailure>()),
      );
    });
  });

  group('ProfileRepository', () {
    final profileRow = {
      'id': 'u1',
      'display_name': 'Asha',
      'avatar_url': null,
      'email': 'a@example.com',
      'group_id': null,
      'currency': 'USD',
      'timezone': 'Asia/Kolkata',
      'locale': 'en-IN',
      'theme_mode': 'system',
      'haptics_enabled': true,
      'ai_consent': false,
      'ai_consent_at': null,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    };

    test('update writes only the changed column', () async {
      server.respond = (_) => json([profileRow]);
      final repo = SupabaseProfileRepository(server.client());
      final saved = await repo.update('u1', ProfileUpdate(currency: 'USD'));
      expect(saved.currency, 'USD');
      expect(server.last.method, 'PATCH');
      expect(server.lastJsonBody, {'currency': 'USD'});
      expect(server.last.url.queryParameters['id'], 'eq.u1');
    });

    test('a missing profile is not replaced by a stub', () async {
      server.respond = (_) => json([]);
      final repo = SupabaseProfileRepository(server.client());
      await expectLater(
        repo.fetch('u1'),
        throwsA(const AppFailure.notFound(key: 'profile_not_found')),
      );
    });

    test('invalid input is rejected before any request', () async {
      final repo = SupabaseProfileRepository(server.client());
      await expectLater(
        repo.update('u1', ProfileUpdate(avatarUrl: 'http://insecure')),
        throwsA(isA<ValidationFailure>()),
      );
      expect(server.requests, isEmpty);
    });
  });

  group('GroupRepository', () {
    test('a failed code join throws the server reason', () async {
      server.respond = (_) => json({
        'success': false,
        'error': 'rate_limited',
        'retry_after': '2026-11-15T18:00:00Z',
      });
      final repo = SupabaseGroupRepository(server.client());
      final failure = await repo
          .joinByCode('ABCD-EFGH')
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(failure, isA<RateLimitedFailure>());
      expect(
        (failure! as RateLimitedFailure).retryAfter,
        DateTime.utc(2026, 11, 15, 18),
      );
    });

    test('a code join is a pending request', () async {
      server.respond = (_) => json({
        'success': true,
        'group_id': 'g1',
        'group_name': 'Flat',
        'role': 'viewer',
        'status': 'pending',
      });
      final repo = SupabaseGroupRepository(server.client());
      final request = await repo.joinByCode('abcd');
      expect(request.status, MemberStatus.pending);
      expect(server.last.url.path, '/rest/v1/rpc/join_group_by_code');
    });

    test('set_active_group sends null for personal mode', () async {
      server.respond = (_) => json({'group_id': null});
      final repo = SupabaseGroupRepository(server.client());
      await repo.setActiveGroup(null);
      expect(server.lastJsonBody, {'p_group_id': null});
    });

    test('a group is deleted through delete_group', () async {
      server.respond = (_) => json({'group_id': 'g1', 'deleted': true});
      final repo = SupabaseGroupRepository(server.client());
      await repo.deleteGroup('g1');
      expect(server.last.url.path, '/rest/v1/rpc/delete_group');
      expect(server.lastJsonBody, {'p_group_id': 'g1'});
    });

    test('a group with other members cannot be deleted', () async {
      server.respond = (_) =>
          json({'code': 'P0001', 'message': 'group_has_members'}, 400);
      final repo = SupabaseGroupRepository(server.client());
      final failure = await repo
          .deleteGroup('g1')
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(failure, const AppFailure.business('group_has_members'));
    });

    test('remove_member sends p_force and maps an open balance', () async {
      server.respond = (_) => json({
        'code': 'P0001',
        'message': 'outstanding_balance',
        'details': 'net_minor=-500 pending_minor=0',
      }, 400);
      final repo = SupabaseGroupRepository(server.client());
      final failure = await repo
          .removeMember('g1', 'u2')
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(failure, const AppFailure.business('outstanding_balance'));
      expect(server.lastJsonBody, {
        'p_group_id': 'g1',
        'p_user_id': 'u2',
        'p_force': false,
      });

      server.respond = (_) => json({'removed': true});
      await repo.removeMember('g1', 'u2', force: true);
      expect(server.lastJsonBody['p_force'], isTrue);
    });

    test('members come from get_group_members', () async {
      server.respond = (_) => json([
        {
          'user_id': 'u1',
          'display_name': 'Asha',
          'avatar_url': null,
          'role': 'admin',
          'status': 'approved',
          'joined_at': '2026-01-01T00:00:00Z',
        },
        {
          'user_id': 'u2',
          'display_name': 'Ravi',
          'avatar_url': null,
          'role': 'member',
          'status': 'approved',
          'joined_at': '2026-01-02T00:00:00Z',
        },
      ]);
      final repo = SupabaseGroupRepository(server.client());
      final members = await repo.fetchMembers('g1');
      expect(members.map((m) => m.userId), ['u1', 'u2']);
    });
  });

  group('Edge Functions', () {
    test('send-invite returns an honest not-sent result', () async {
      server.respond = (_) => json({
        'invitation_id': 'i1',
        'sent': false,
        'reason': 'email_failed',
        'expires_at': '2026-11-22T00:00:00Z',
        'share_url': 'https://exevra.app/invite/tok',
      });
      final repo = SupabaseInvitationRepository(server.client());
      final result = await repo.send(groupId: 'g1', email: ' A@Example.com ');
      expect(result.sent, isFalse);
      expect(result.shareUrl, 'https://exevra.app/invite/tok');
      expect(server.last.url.path, '/functions/v1/send-invite');
      expect(server.lastJsonBody, {
        'group_id': 'g1',
        'email': 'a@example.com',
        'role': 'member',
      });
    });

    test('send-invite maps a typed error', () async {
      server.respond = (_) => json({
        'error': {
          'code': 'forbidden',
          'message': 'Only admins',
          'reason': 'not_group_admin',
        },
      }, 403);
      final repo = SupabaseInvitationRepository(server.client());
      await expectLater(
        repo.send(groupId: 'g1', email: 'a@example.com'),
        throwsA(const AppFailure.permissionDenied(key: 'not_group_admin')),
      );
    });

    test('delete-account failure keeps the account', () async {
      server.respond = (_) => json({
        'error': {'code': 'deletion_failed', 'message': 'x'},
      }, 500);
      final repo = SupabaseAccountRepository(server.client());
      await expectLater(
        repo.deleteAccount(),
        throwsA(const AppFailure.business('deletion_failed')),
      );
    });

    test('delete-account success', () async {
      server.respond = (_) => json({'deleted': true, 'apple_revoked': false});
      final repo = SupabaseAccountRepository(server.client());
      await repo.deleteAccount();
      expect(server.last.url.path, '/functions/v1/delete-account');
    });
  });

  group('SettlementRepository', () {
    test('record sends minor units and maps business errors', () async {
      server.respond = (_) =>
          json({'code': 'P0001', 'message': 'settlement_exceeds_debt'}, 400);
      final repo = SupabaseSettlementRepository(server.client());
      await expectLater(
        repo.record(groupId: 'g1', toUser: 'u2', amount: Money(5000, 'INR')),
        throwsA(const AppFailure.business('settlement_exceeds_debt')),
      );
      expect(server.lastJsonBody, {
        'p_group_id': 'g1',
        'p_to_user': 'u2',
        'p_amount_minor': 5000,
        'p_note': null,
      });
    });

    test('zero is rejected before any request', () async {
      final repo = SupabaseSettlementRepository(server.client());
      await expectLater(
        repo.record(groupId: 'g1', toUser: 'u2', amount: Money(0, 'INR')),
        throwsA(isA<ValidationFailure>()),
      );
      expect(server.requests, isEmpty);
    });
  });
}
