import 'dart:async';

import 'package:expense_manager/core/constants/app_constants.dart';
import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/storage/preferences.dart';
import 'package:expense_manager/models/expense.dart';
import 'package:expense_manager/models/balance.dart';
import 'package:expense_manager/models/group.dart';
import 'package:expense_manager/models/invitation.dart';
import 'package:expense_manager/models/money.dart';
import 'package:expense_manager/models/profile.dart';
import 'package:expense_manager/models/settlement.dart';
import 'package:expense_manager/providers/auth_provider.dart';
import 'package:expense_manager/providers/chat_provider.dart';
import 'package:expense_manager/providers/expense_provider.dart';
import 'package:expense_manager/providers/failure_reporter.dart';
import 'package:expense_manager/providers/group_detail_providers.dart';
import 'package:expense_manager/providers/groups_provider.dart';
import 'package:expense_manager/providers/profile_provider.dart';
import 'package:expense_manager/providers/session_guard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  // Haptics and other platform calls need the test binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('user A to user B', () {
    late TestBackend backend;
    late ProviderContainer container;

    setUp(() async {
      backend = TestBackend(signedInAs: 'A');
      backend.profiles.profiles['A'] = profileOf(
        'A',
        activeGroupId: 'gA',
      ).copyWith(themeMode: ThemePreference.dark);
      backend.profiles.profiles['B'] = profileOf('B');
      backend.groups.groupsByUser['A'] = [groupOf('gA', adminId: 'A')];
      backend.groups.groupsByUser['B'] = [groupOf('gB', adminId: 'B')];
      backend.expenses.rows.addAll([
        expenseOf('a-personal', userId: 'A', title: 'A secret'),
        expenseOf('a-group', userId: 'A', groupId: 'gA'),
        expenseOf('b-personal', userId: 'B'),
      ]);
      container = await backend.container(
        prefs: {
          AppConstants.keyThemeMode: 'light',
          UserPrefs.key('A', UserPrefs.haptics): false,
          // A legacy global key that held one user's data.
          AppConstants.keyCurrency: 'USD',
        },
      );
      addTearDown(container.dispose);
    });

    /// Keeps every user-scoped provider alive, as the screens do.
    void watchAll() {
      container
        ..listen(profileProvider, (_, _) {})
        ..listen(userProfileProvider, (_, _) {})
        ..listen(groupsProvider, (_, _) {})
        ..listen(activeGroupProvider, (_, _) {})
        ..listen(scopeExpenseKeyProvider, (_, _) {})
        ..listen(expenseFilterProvider, (_, _) {})
        ..listen(chatProvider, (_, _) {});
    }

    Future<List<Expense>> scopeItems() async {
      final key = container.read(scopeExpenseKeyProvider);
      if (key == null) return const [];
      container.listen(expenseListProvider(key), (_, _) {});
      return (await container.read(expenseListProvider(key).future)).items;
    }

    test('no data of A is visible after B signs in', () async {
      watchAll();
      await container.read(groupsProvider.notifier).loaded;
      await settle();

      // A is loaded.
      expect(container.read(currentUserIdProvider), 'A');
      expect(container.read(userProfileProvider)?.id, 'A');
      expect(container.read(activeGroupProvider)?.id, 'gA');
      final aKey = container.read(scopeExpenseKeyProvider)!;
      expect((await scopeItems()).map((e) => e.id), ['a-personal', 'a-group']);
      container.read(expenseFilterProvider.notifier).setSearch('secret');
      await container.read(chatProvider.notifier).sendMessage('hi A');
      expect(container.read(chatProvider).messages.length, greaterThan(1));

      // A signs out.
      await container.read(authControllerProvider.notifier).signOut();
      await settle();

      expect(container.read(currentUserIdProvider), isNull);
      expect(container.read(userProfileProvider), isNull);
      expect(container.read(activeGroupProvider), isNull);
      expect(container.read(scopeExpenseKeyProvider), isNull);
      expect(container.read(groupsProvider).value?.groups ?? const [], isEmpty);
      // A's list (if anything still holds it) is emptied.
      expect(container.read(expenseListProvider(aKey)).value?.items, isEmpty);

      // Per-user preferences are gone; the device theme (A's choice,
      // copied from the server) stays.
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getKeys().where((k) => k.startsWith('u.A.')), isEmpty);
      expect(prefs.containsKey(AppConstants.keyCurrency), isFalse);
      expect(prefs.getString(AppConstants.keyThemeMode), 'dark');
      expect(container.read(themePreferenceProvider), ThemePreference.dark);

      // B signs in.
      backend.auth.signInAs('B');
      await settle();
      await container.read(groupsProvider.notifier).loaded;
      await settle();

      expect(container.read(currentUserIdProvider), 'B');
      expect(container.read(userProfileProvider)?.id, 'B');
      expect(container.read(groupsProvider).value!.groups.map((g) => g.id), [
        'gB',
      ]);
      expect(container.read(activeGroupProvider), isNull);
      expect(container.read(expenseFilterProvider), const ExpenseFilter());
      expect(container.read(chatProvider).messages.length, 1);
      expect(
        container.read(chatProvider).messages.any((m) => m.text == 'hi A'),
        isFalse,
      );
      final items = await scopeItems();
      expect(items.map((e) => e.id), ['b-personal']);
      expect(items.any((e) => e.userId == 'A'), isFalse);
      expect(container.read(scopeExpenseKeyProvider)!.userId, 'B');
    });

    Future<void> switchToB() async {
      await container.read(authControllerProvider.notifier).signOut();
      await settle();
      backend.auth.signInAs('B');
      await settle();
      await container.read(groupsProvider.notifier).loaded;
      await settle();
    }

    test('A\'s groups refresh that ends after B signs in is dropped', () async {
      watchAll();
      await container.read(groupsProvider.notifier).loaded;
      await settle();

      final held = Completer<List<Group>>();
      backend.groups.heldFetches.add(held);
      final refreshing = container.read(groupsProvider.notifier).refresh();
      await switchToB();
      expect(container.read(groupsProvider).value!.groups.map((g) => g.id), [
        'gB',
      ]);

      held.complete([groupOf('gA', adminId: 'A')]);
      expect(await refreshing, SessionGuard.dropped);
      await settle();

      final state = container.read(groupsProvider).value!;
      expect(state.userId, 'B');
      expect(state.groups.map((g) => g.id), ['gB']);
    });

    test('A\'s profile update that ends after B signs in is dropped', () async {
      watchAll();
      await container.read(groupsProvider.notifier).loaded;
      await settle();

      final release = Completer<void>();
      backend.profiles.holdUpdates = release;
      final updating = container
          .read(profileProvider.notifier)
          .setHapticsEnabled(true);
      await switchToB();
      backend.profiles.holdUpdates = null;
      expect(container.read(userProfileProvider)?.id, 'B');

      release.complete();
      await updating;
      await settle();

      expect(container.read(profileProvider).value?.id, 'B');
      expect(container.read(userProfileProvider)?.id, 'B');
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getKeys().where((k) => k.startsWith('u.A.')), isEmpty);
    });
  });

  group('user-scoped data while the next user loads or fails', () {
    late TestBackend backend;
    late ProviderContainer container;

    // A and B share group gS; A is its admin and sees admin-only data.
    setUp(() async {
      backend = TestBackend(signedInAs: 'A')
        ..invitations = FakeInvitationRepository();
      backend.profiles.profiles['A'] = profileOf('A', activeGroupId: 'gS');
      backend.profiles.profiles['B'] = profileOf('B');
      backend.groups.groupsByUser['A'] = [groupOf('gS', adminId: 'A')];
      backend.groups.groupsByUser['B'] = [
        groupOf('gS', adminId: 'A', role: GroupRole.member),
      ];
      backend.groups.membersByGroup['gS'] = [
        memberOf('A', role: GroupRole.admin),
        memberOf('B'),
        memberOf('C', status: MemberStatus.pending),
      ];
      backend.balances.balancesByGroup['gS'] = [
        balanceOf('A', 500),
        balanceOf('B', -500),
      ];
      backend.balances.suggestionsByGroup['gS'] = [
        SettleSuggestion(fromUser: 'B', toUser: 'A', amount: Money(500, 'INR')),
      ];
      backend.settlements.rows.add(
        Settlement(
          id: 's1',
          groupId: 'gS',
          fromUser: 'B',
          toUser: 'A',
          amount: Money(200, 'INR'),
          status: SettlementStatus.pending,
          createdAt: DateTime.utc(2026, 11, 9),
        ),
      );
      backend.invitations!.pending.add(
        GroupInvitation(
          id: 'inv-A',
          groupId: 'gS',
          inviterId: 'A',
          email: 'friend-of-a@example.com',
          role: GroupRole.member,
          status: InvitationStatus.pending,
          expiresAt: DateTime.utc(2026, 12),
          createdAt: DateTime.utc(2026, 11),
        ),
      );
      container = await backend.container();
      addTearDown(container.dispose);
    });

    /// Every user-scoped provider, kept alive as the screens do.
    Map<String, ProviderListenable<AsyncValue<Object?>>> scoped() => {
      'profile': profileProvider,
      'groups': groupsProvider,
      'members': groupMembersProvider('gS'),
      'balances': groupBalancesProvider('gS'),
      'suggestions': settleSuggestionsProvider('gS'),
      'pending payments': pendingSettlementsProvider('gS'),
      'payments': settlementsProvider('gS'),
      'payment events': settlementEventsProvider('s1'),
      'invitations': pendingInvitationsProvider('gS'),
    };

    void watchAll() {
      for (final p in scoped().values) {
        container.listen(p, (_, _) {});
      }
      container
        ..listen(userProfileProvider, (_, _) {})
        ..listen(activeGroupProvider, (_, _) {})
        ..listen(currentGroupsProvider, (_, _) {})
        ..listen(activeGroupMembersProvider, (_, _) {});
    }

    void expectNothingOf(String phase, {required bool failed}) {
      for (final MapEntry(key: name, value: p) in scoped().entries) {
        final value = container.read(p);
        expect(value.hasValue, isFalse, reason: '$name $phase: $value');
        if (failed) {
          expect(value.hasError, isTrue, reason: '$name $phase: $value');
        } else if (!failed) {
          expect(value.isLoading, isTrue, reason: '$name $phase: $value');
        }
      }
      expect(container.read(userProfileProvider), isNull);
      expect(container.read(activeGroupProvider), isNull);
      expect(container.read(currentGroupsProvider), isNull);
      expect(container.read(activeGroupMembersProvider).value ?? [], isEmpty);
      expect(container.read(groupsReadyProvider), failed);
    }

    test('nothing of A shows while B loads or after B failed', () async {
      watchAll();
      await settle(20);
      for (final MapEntry(key: name, value: p) in scoped().entries) {
        expect(container.read(p).hasValue, isTrue, reason: '$name for A');
      }
      expect(container.read(activeGroupProvider)?.id, 'gS');
      expect(container.read(activeGroupMembersProvider).value, hasLength(3));

      // B's data is held on its way.
      final hold = Completer<void>();
      backend.reads.hold = hold;
      await container.read(authControllerProvider.notifier).signOut();
      await settle();
      backend.auth.signInAs('B');
      await settle(20);
      expect(container.read(currentUserIdProvider), 'B');
      expectNothingOf('while B loads', failed: false);

      // B's data fails to load.
      backend.reads.failure = const AppFailure.network();
      hold.complete();
      await settle(20);
      expectNothingOf('after B failed', failed: true);
    });
  });

  group('overlapping scope switches', () {
    late TestBackend backend;
    late ProviderContainer container;

    setUp(() async {
      backend = TestBackend(signedInAs: 'A');
      backend.profiles.profiles['A'] = profileOf('A');
      backend.groups.groupsByUser['A'] = [
        groupOf('g1', adminId: 'A'),
        groupOf('g2', adminId: 'A'),
      ];
      container = await backend.container();
      addTearDown(container.dispose);
      container.listen(groupsProvider, (_, _) {});
      await container.read(groupsProvider.notifier).loaded;
      await settle();
    });

    test('a late failure of an earlier switch keeps the latest', () async {
      final first = Completer<void>();
      backend.groups.heldSetActive.add(first);
      backend.groups.failSetActiveFor.add('g1');
      final notifier = container.read(groupsProvider.notifier);

      final a = notifier.switchScope('g1');
      final b = notifier.switchScope('g2');
      first.complete();
      expect(await a, isA<NetworkFailure>());
      expect(await b, isNull);

      expect(container.read(activeGroupProvider)?.id, 'g2');
      expect(backend.groups.serverActiveGroup, 'g2');
      expect(container.read(userProfileProvider)?.activeGroupId, 'g2');
      expect(container.read(failureReporterProvider), isNull);
    });

    test('writes reach the server in the order of the taps', () async {
      final first = Completer<void>();
      backend.groups.heldSetActive.add(first);
      final notifier = container.read(groupsProvider.notifier);

      final a = notifier.switchScope('g1');
      final b = notifier.switchScope('g2');
      await settle();
      // The second write waits for the first.
      expect(backend.groups.activeGroupWrites, isEmpty);
      first.complete();
      await Future.wait([a, b]);

      expect(backend.groups.activeGroupWrites, ['g1', 'g2']);
      expect(backend.groups.serverActiveGroup, 'g2');
      expect(container.read(activeGroupProvider)?.id, 'g2');
    });

    test('when the latest switch fails the server\'s scope returns', () async {
      final first = Completer<void>();
      backend.groups.heldSetActive.add(first);
      backend.groups.failSetActiveFor.add('g2');
      final notifier = container.read(groupsProvider.notifier);

      final a = notifier.switchScope('g1');
      final b = notifier.switchScope('g2');
      first.complete();
      expect(await a, isNull);
      expect(await b, isA<NetworkFailure>());

      expect(backend.groups.serverActiveGroup, 'g1');
      expect(container.read(activeGroupProvider)?.id, 'g1');
      expect(container.read(userProfileProvider)?.activeGroupId, 'g1');
    });
  });

  group('active scope', () {
    late TestBackend backend;
    late ProviderContainer container;

    setUp(() async {
      backend = TestBackend(signedInAs: 'A');
      backend.profiles.profiles['A'] = profileOf('A');
      backend.groups.groupsByUser['A'] = [
        groupOf('g1', adminId: 'A'),
        groupOf(
          'pending',
          adminId: 'Z',
          role: GroupRole.viewer,
          status: MemberStatus.pending,
        ),
      ];
      container = await backend.container();
      addTearDown(container.dispose);
      container.listen(groupsProvider, (_, _) {});
      await container.read(groupsProvider.notifier).loaded;
      await settle();
    });

    test('switching writes the server once', () async {
      final failure = await container
          .read(groupsProvider.notifier)
          .switchScope('g1');
      expect(failure, isNull);
      expect(backend.groups.activeGroupWrites, ['g1']);
      expect(container.read(activeGroupProvider)?.id, 'g1');
      expect(container.read(userProfileProvider)?.activeGroupId, 'g1');

      // Selecting the same scope again does not write.
      await container.read(groupsProvider.notifier).switchScope('g1');
      expect(backend.groups.activeGroupWrites, ['g1']);

      // Back to personal mode (null is a real value, not "unchanged").
      await container.read(groupsProvider.notifier).switchScope(null);
      expect(backend.groups.activeGroupWrites, ['g1', null]);
      expect(container.read(activeGroupProvider), isNull);
      expect(container.read(userProfileProvider)?.activeGroupId, isNull);
    });

    test('a failed switch restores the previous scope', () async {
      backend.groups.failSetActive = const AppFailure.permissionDenied(
        key: 'not_group_member',
      );
      final failure = await container
          .read(groupsProvider.notifier)
          .switchScope('g1');
      expect(failure, isA<PermissionDeniedFailure>());
      expect(container.read(activeGroupProvider), isNull);
      expect(
        container.read(failureReporterProvider)?.failure,
        isA<PermissionDeniedFailure>(),
      );
    });

    test('a saved pending group is not opened', () async {
      final state = container.read(groupsProvider).value!;
      expect(state.pendingGroups.map((g) => g.id), ['pending']);
      expect(state.approvedGroups.map((g) => g.id), ['g1']);
      expect(container.read(activeGroupProvider), isNull);
    });
  });

  group('profile', () {
    test('a failed profile load is retried with the groups', () async {
      final backend = TestBackend(signedInAs: 'A');
      backend.profiles.profiles['A'] = profileOf('A', activeGroupId: 'g1');
      backend.groups.groupsByUser['A'] = [groupOf('g1', adminId: 'A')];
      backend.profiles.failFetch = const AppFailure.network();
      final container = await backend.container();
      addTearDown(container.dispose);
      container
        ..listen(profileProvider, (_, _) {})
        ..listen(groupsProvider, (_, _) {});
      await settle();
      expect(container.read(groupsProvider).hasError, isTrue);

      // Without a profile a settings change says so (not "session expired").
      final failure = await container
          .read(profileProvider.notifier)
          .setCurrency('USD');
      expect(failure, const AppFailure.notFound(key: 'profile_not_found'));

      backend.profiles.failFetch = null;
      container.read(groupsProvider.notifier).retry();
      await container.read(groupsProvider.notifier).loaded;
      await settle();

      expect(container.read(userProfileProvider)?.id, 'A');
      expect(container.read(activeGroupProvider)?.id, 'g1');
    });

    test('a failed preference update rolls back', () async {
      final backend = TestBackend(signedInAs: 'A');
      backend.profiles.profiles['A'] = profileOf('A');
      final container = await backend.container();
      addTearDown(container.dispose);
      container.listen(profileProvider, (_, _) {});
      await container.read(profileProvider.notifier).loaded;
      await settle();

      backend.profiles.failUpdates = const AppFailure.offline();
      final failure = await container
          .read(profileProvider.notifier)
          .setCurrency('USD');

      expect(failure, isA<OfflineFailure>());
      expect(container.read(userProfileProvider)?.currency, 'INR');
    });

    group('overlapping preference updates', () {
      late TestBackend backend;
      late ProviderContainer container;

      setUp(() async {
        backend = TestBackend(signedInAs: 'A');
        backend.profiles.profiles['A'] = profileOf('A');
        container = await backend.container();
        addTearDown(container.dispose);
        container.listen(profileProvider, (_, _) {});
        await settle(10);
        expect(container.read(userProfileProvider)?.currency, 'INR');
        backend.profiles.updates.clear();
      });

      ProfileNotifier notifier() => container.read(profileProvider.notifier);
      UserProfile? shown() => container.read(userProfileProvider);

      (Completer<void>, Completer<void>) holdTwo() {
        final first = Completer<void>();
        final second = Completer<void>();
        backend.profiles.heldUpdates.addAll([first, second]);
        return (first, second);
      }

      test('an older failure does not undo a newer confirmed write', () async {
        final (first, second) = holdTwo();
        final older = notifier().setCurrency('USD');
        final newer = notifier().setCurrency('EUR');
        await settle();
        expect(shown()?.currency, 'EUR');

        second.complete();
        expect(await newer, isNull);
        first.completeError(const AppFailure.network());
        expect(await older, isA<NetworkFailure>());
        await settle();

        expect(shown()?.currency, 'EUR');
        expect(backend.profiles.profiles['A']?.currency, 'EUR');
      });

      test('a failure only rolls back the columns it wrote', () async {
        final (first, second) = holdTwo();
        final currency = notifier().setCurrency('USD');
        final haptics = notifier().setHapticsEnabled(false);
        await settle();

        second.complete();
        expect(await haptics, isNull);
        first.completeError(const AppFailure.network());
        expect(await currency, isA<NetworkFailure>());
        await settle();

        expect(shown()?.currency, 'INR');
        expect(shown()?.hapticsEnabled, isFalse);
      });

      test('an older success does not hide a newer write on its way', () async {
        final (first, second) = holdTwo();
        final older = notifier().setCurrency('USD');
        final newer = notifier().setCurrency('EUR');
        await settle();

        first.complete();
        expect(await older, isNull);
        await settle();
        expect(shown()?.currency, 'EUR');

        second.completeError(const AppFailure.network());
        expect(await newer, isA<NetworkFailure>());
        await settle();
        // The newer write failed: the confirmed older one shows.
        expect(shown()?.currency, 'USD');
      });
    });

    test('updates send only the changed column', () async {
      final backend = TestBackend(signedInAs: 'A');
      backend.profiles.profiles['A'] = profileOf('A');
      final container = await backend.container();
      addTearDown(container.dispose);
      container.listen(profileProvider, (_, _) {});
      await container.read(profileProvider.notifier).loaded;
      await settle();
      backend.profiles.updates.clear();

      await container.read(profileProvider.notifier).setHapticsEnabled(false);

      expect(backend.profiles.updates.single.$2.fields, {
        'haptics_enabled': false,
      });
    });
  });
}
