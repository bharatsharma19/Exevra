import 'dart:async';

import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/data/ai/ai_chat_client.dart';
import 'package:expense_manager/data/ai/ai_chat_models.dart';
import 'package:expense_manager/models/expense.dart';
import 'package:expense_manager/models/group.dart';
import 'package:expense_manager/models/invitation.dart';
import 'package:expense_manager/models/money.dart';
import 'package:expense_manager/providers/auth_provider.dart';
import 'package:expense_manager/providers/chat_provider.dart';
import 'package:expense_manager/providers/data_revision.dart';
import 'package:expense_manager/providers/expense_provider.dart';
import 'package:expense_manager/providers/failure_reporter.dart';
import 'package:expense_manager/providers/group_detail_providers.dart';
import 'package:expense_manager/providers/groups_provider.dart';
import 'package:expense_manager/providers/profile_provider.dart';
import 'package:expense_manager/providers/session_guard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/chat_test_support.dart';
import '../support/fakes.dart';

/// Actions user A started that end after the session changed: nothing of
/// them reaches the next session (state, follow-up calls, reports).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestBackend backend;
  late ProviderContainer container;
  late FakeAiChatApi assistant;

  setUp(() async {
    backend = TestBackend(signedInAs: 'A')
      ..invitations = FakeInvitationRepository();
    backend.profiles.profiles['A'] = profileOf(
      'A',
      activeGroupId: 'gS',
    ).copyWith(aiConsent: true);
    backend.profiles.profiles['B'] = profileOf('B').copyWith(aiConsent: true);
    backend.groups.groupsByUser['A'] = [
      groupOf('gS', adminId: 'A'),
      groupOf('g2', adminId: 'A'),
    ];
    backend.groups.groupsByUser['B'] = [groupOf('gB', adminId: 'B')];
    backend.groups.membersByGroup['gS'] = [
      memberOf('A', role: GroupRole.admin),
      memberOf('C', status: MemberStatus.pending),
    ];
    backend.expenses.rows.add(expenseOf('a1', userId: 'A'));
    backend.invitations!.pending.add(
      GroupInvitation(
        id: 'inv-A',
        groupId: 'gS',
        inviterId: 'A',
        email: 'friend@example.com',
        role: GroupRole.member,
        status: InvitationStatus.pending,
        expiresAt: DateTime.utc(2026, 12),
        createdAt: DateTime.utc(2026, 11),
      ),
    );
    assistant = FakeAiChatApi();
    container = await backend.container(
      extraOverrides: [aiChatApiProvider.overrideWithValue(assistant)],
    );
    addTearDown(container.dispose);
    container
      ..listen(profileProvider, (_, _) {})
      ..listen(groupsProvider, (_, _) {})
      ..listen(failureReporterProvider, (_, _) {})
      ..listen(chatProvider, (_, _) {});
    await container.read(groupsProvider.notifier).loaded;
    await settle();
    expect(container.read(activeGroupProvider)?.id, 'gS');
  });

  GroupsNotifier groups() => container.read(groupsProvider.notifier);

  Future<void> signOutAndIn(String user) async {
    await container.read(authControllerProvider.notifier).signOut();
    await settle();
    backend.auth.signInAs(user);
    await settle();
    await container.read(groupsProvider.notifier).loaded;
    await settle();
  }

  /// B sees only B's data, with nothing reported and no scope written.
  void expectBUntouched({List<String?> scopeWrites = const []}) {
    expect(container.read(currentUserIdProvider), 'B');
    expect(container.read(failureReporterProvider), isNull);
    final state = container.read(groupsProvider).value!;
    expect(state.userId, 'B');
    expect(state.groups.map((g) => g.id), ['gB']);
    expect(state.activeGroupId, isNull);
    expect(backend.groups.activeGroupWrites, scopeWrites);
    expect(container.read(userProfileProvider)?.id, 'B');
    expect(container.read(userProfileProvider)?.activeGroupId, isNull);
  }

  group('groups', () {
    test('a group A creates is not opened for B (held refresh)', () async {
      final held = Completer<List<Group>>();
      backend.groups.heldFetches.add(held);
      final creating = groups().createGroup('Trip', currency: 'INR');
      await settle();
      expect(backend.groups.calls, ['create:Trip:INR']);

      await signOutAndIn('B');
      held.complete(backend.groups.groupsByUser['A']!);
      final result = await creating;
      await settle();

      expect(result.status, GroupCreateStatus.failed);
      expect(result.failure, SessionGuard.dropped);
      expectBUntouched();
    });

    test('a failed refresh after A\'s create is not shown to B', () async {
      final held = Completer<List<Group>>();
      backend.groups.heldFetches.add(held);
      final creating = groups().createGroup('Trip', currency: 'INR');
      await settle();

      await signOutAndIn('B');
      held.completeError(const AppFailure.network());
      expect((await creating).failure, SessionGuard.dropped);
      await settle();

      expectBUntouched();
    });

    test('signing out and back in as A is a new session', () async {
      final held = Completer<List<Group>>();
      backend.groups.heldFetches.add(held);
      final creating = groups().createGroup('Trip', currency: 'INR');
      await settle();

      await signOutAndIn('A');
      held.complete(backend.groups.groupsByUser['A']!);
      expect((await creating).failure, SessionGuard.dropped);
      await settle();

      expect(backend.groups.activeGroupWrites, isEmpty);
      expect(container.read(failureReporterProvider), isNull);
      expect(container.read(activeGroupProvider)?.id, 'gS');
    });

    test('a queued scope write of A is never sent as B', () async {
      final first = Completer<void>();
      backend.groups.heldSetActive.add(first);
      backend.groups.failSetActiveFor.add('g2');
      final a = groups().switchScope(null);
      final b = groups().switchScope('g2');
      await settle();

      await signOutAndIn('B');
      first.complete();
      expect(await a, SessionGuard.dropped);
      expect(await b, SessionGuard.dropped);
      await settle();

      // Only the write already on its way when A left reached the server.
      expectBUntouched(scopeWrites: [null]);
    });

    test('a failed join request of A is not reported to B', () async {
      backend.groups
        ..holdActions = Completer<void>()
        ..failActions = const AppFailure.network();
      final joining = groups().joinByCode('ABCD');
      await settle();

      await signOutAndIn('B');
      backend.groups.holdActions!.complete();
      expect(await joining, (null, SessionGuard.dropped));
      await settle();

      expectBUntouched();
    });

    test('a rotated code of A does not reload B\'s groups', () async {
      backend.groups.holdActions = Completer<void>();
      final rotating = groups().rotateInviteCode('gS');
      await settle();

      await signOutAndIn('B');
      final fetches = backend.groups.fetchCalls;
      backend.groups.holdActions!.complete();
      expect(await rotating, (null, SessionGuard.dropped));
      await settle();

      expect(backend.groups.fetchCalls, fetches);
      expectBUntouched();
    });
  });

  group('group details', () {
    test('a member change of A is neither reported nor reloaded', () async {
      container.listen(groupMembersProvider('gS'), (_, _) {});
      await container.read(groupMembersProvider('gS').notifier).loaded;
      backend.groups
        ..holdActions = Completer<void>()
        ..failActions = const AppFailure.network();
      final failing = container
          .read(groupMembersProvider('gS').notifier)
          .approve('C');
      await settle();

      await signOutAndIn('B');
      backend.groups.holdActions!.complete();
      expect(await failing, SessionGuard.dropped);
      await settle();
      expectBUntouched();

      // A success does not reload anything either.
      backend.groups
        ..holdActions = null
        ..failActions = null;
      await signOutAndIn('A');
      backend.groups.holdActions = Completer<void>();
      final approving = container
          .read(groupMembersProvider('gS').notifier)
          .approve('C');
      await settle();
      await signOutAndIn('B');
      final members = container.read(dataRevisionProvider).members;
      final fetches = backend.groups.fetchCalls;
      backend.groups.holdActions!.complete();
      expect(await approving, SessionGuard.dropped);
      await settle();

      expect(container.read(dataRevisionProvider).members, members);
      expect(backend.groups.fetchCalls, fetches);
      expectBUntouched();
    });

    test('an unconfirmed payment of A is not reported to B', () async {
      container.listen(settlementsProvider('gS'), (_, _) {});
      await container.read(settlementsProvider('gS').notifier).loaded;
      backend.settlements
        ..holdWrites = Completer<void>()
        ..failWrites = const AppFailure.timeout();
      final recording = container
          .read(settlementsProvider('gS').notifier)
          .record(toUser: 'C', amount: Money(100, 'INR'));
      await settle();

      await signOutAndIn('B');
      final revision = container.read(dataRevisionProvider).settlements;
      backend.settlements.holdWrites!.complete();
      expect(await recording, SessionGuard.dropped);
      await settle();

      expect(container.read(dataRevisionProvider).settlements, revision);
      expectBUntouched();
    });

    test('invitation writes of A are not reported to B', () async {
      container.listen(pendingInvitationsProvider('gS'), (_, _) {});
      await container.read(pendingInvitationsProvider('gS').notifier).loaded;
      final invitations = backend.invitations!
        ..holdWrites = Completer<void>()
        ..failSend = const AppFailure.network()
        ..failRevoke = const AppFailure.network();
      final notifier = container.read(
        pendingInvitationsProvider('gS').notifier,
      );
      final sending = notifier.send('someone@example.com');
      final revoking = notifier.revoke('inv-A');
      await settle();

      await signOutAndIn('B');
      await container.read(pendingInvitationsProvider('gS').notifier).loaded;
      final shownToB = container.read(pendingInvitationsProvider('gS')).value;
      invitations.holdWrites!.complete();
      expect(await sending, (null, SessionGuard.dropped));
      expect(await revoking, SessionGuard.dropped);
      await settle();

      expect(container.read(pendingInvitationsProvider('gS')).value, shownToB);
      expectBUntouched();
    });
  });

  group('profile', () {
    test('a failed profile write of A is not reported to B', () async {
      backend.profiles
        ..holdUpdates = Completer<void>()
        ..failUpdates = const AppFailure.network();
      final updating = container
          .read(profileProvider.notifier)
          .setCurrency('USD');
      await settle();

      await signOutAndIn('B');
      final release = backend.profiles.holdUpdates!;
      backend.profiles.holdUpdates = null;
      release.complete();
      expect(await updating, SessionGuard.dropped);
      backend.profiles.failUpdates = null;
      await settle();

      expect(container.read(userProfileProvider)?.currency, 'INR');
      expectBUntouched();
    });

    test('a reload that started before a write keeps that write', () async {
      final write = Completer<void>();
      backend.profiles.heldUpdates.add(write);
      final updating = container
          .read(profileProvider.notifier)
          .setCurrency('USD');
      await settle();

      // A reload reads the row before the write lands.
      final read = Completer<void>();
      backend.reads.hold = read;
      container
        ..invalidate(profileProvider)
        ..read(profileProvider);
      await settle();
      write.complete();
      expect(await updating, isNull);
      expect(container.read(userProfileProvider)?.currency, 'USD');

      // What that read returns predates the write; another column changed
      // on the server meanwhile.
      backend.profiles.profiles['A'] = backend.profiles.profiles['A']!.copyWith(
        currency: 'INR',
        displayName: 'Renamed elsewhere',
      );
      backend.reads.hold = null;
      read.complete();
      await settle(10);

      final shown = container.read(userProfileProvider)!;
      expect(shown.currency, 'USD');
      expect(shown.displayName, 'Renamed elsewhere');

      // A reload that starts after the write takes the server's value.
      backend.profiles.profiles['A'] = backend.profiles.profiles['A']!.copyWith(
        currency: 'EUR',
      );
      container.invalidate(profileProvider);
      await container.read(profileProvider.notifier).loaded;
      await settle();
      expect(container.read(userProfileProvider)?.currency, 'EUR');
    });
  });

  group('expenses', () {
    Future<ExpenseListNotifier> listOfA() async {
      final key = container.read(scopeExpenseKeyProvider)!;
      expect(key.userId, 'A');
      container.listen(expenseListProvider(key), (_, _) {});
      await container.read(expenseListProvider(key).future);
      return container.read(expenseListProvider(key).notifier);
    }

    test('an unconfirmed add of A is neither reported nor reloaded', () async {
      final list = await listOfA();
      backend.expenses
        ..holdWrites = Completer<void>()
        ..failWrites = const AppFailure.network();
      final adding = list.add(
        ExpenseDraft(
          title: 'Taxi',
          amount: Money(500, 'INR'),
          category: 'Food',
          spentAt: DateTime.utc(2026, 11, 2),
        ),
      );
      await settle();

      await signOutAndIn('B');
      final revision = container.read(dataRevisionProvider).expenses;
      backend.expenses.holdWrites!.complete();
      expect(await adding, SessionGuard.dropped);
      await settle();

      expect(container.read(dataRevisionProvider).expenses, revision);
      expectBUntouched();
    });

    test('a move of A is not sent as B after its edit', () async {
      final list = await listOfA();
      final original = backend.expenses.rows.single;
      backend.expenses.holdWrites = Completer<void>();
      final moving = list.move(
        original,
        ExpenseDraft(
          title: 'Edited first',
          amount: original.amount,
          category: original.category,
          spentAt: original.spentAt,
          groupId: 'gS',
        ),
      );
      await settle();

      await signOutAndIn('B');
      backend.expenses.holdWrites!.complete();
      expect((await moving).failure, SessionGuard.dropped);
      await settle();

      expect(backend.expenses.moves, isEmpty);
      expectBUntouched();
    });
  });

  test('an assistant reply for A is not shown to B', () async {
    final sending = container.read(chatProvider.notifier).sendMessage('hi');
    await settle();
    expect(container.read(chatProvider).isStreaming, isTrue);

    await signOutAndIn('B');
    await assistant.last.finish([const AiDelta('A\'s answer'), const AiDone()]);
    await sending;
    await settle();

    final chat = container.read(chatProvider);
    expect(chat.messages, isEmpty);
    expect(chat.isStreaming, isFalse);
    expect(chat.messages.any((m) => m.text == 'A\'s answer'), isFalse);
  });

  test('no failure is reported while signed out', () async {
    await container.read(authControllerProvider.notifier).signOut();
    await settle();
    container
        .read(failureReporterProvider.notifier)
        .report(const AppFailure.network());
    expect(container.read(failureReporterProvider), isNull);
  });
}
