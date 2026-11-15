import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/providers/failure_reporter.dart';
import 'package:expense_manager/providers/groups_provider.dart';
import 'package:expense_manager/providers/profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  // Haptics need the test binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestBackend backend;
  late ProviderContainer container;

  Future<void> start({String? activeGroupId}) async {
    backend = TestBackend(signedInAs: 'A');
    backend.profiles.profiles['A'] = profileOf(
      'A',
      activeGroupId: activeGroupId,
    );
    backend.groups.groupsByUser['A'] = [groupOf('g1', adminId: 'A')];
    container = await backend.container();
    addTearDown(container.dispose);
    container.listen(groupsProvider, (_, _) {});
    await container.read(groupsProvider.notifier).loaded;
    await settle();
  }

  GroupsNotifier notifier() => container.read(groupsProvider.notifier);
  List<String> serverGroupNames() =>
      backend.groups.groupsByUser['A']!.map((g) => g.name).toList();

  group('createGroup', () {
    test('a created group that cannot be opened is not a failure', () async {
      await start();
      backend.groups.failSetActive = const AppFailure.network();

      final result = await notifier().createGroup(
        'Trip',
        currency: 'INR',
        report: false,
      );

      expect(result.status, GroupCreateStatus.createdNotOpened);
      expect(result.created, isTrue);
      expect(serverGroupNames(), ['Trip', 'Group g1']);
      final state = container.read(groupsProvider).value!;
      expect(state.groups.map((g) => g.name), contains('Trip'));
      expect(state.activeGroupId, isNull);
      // A form shows it itself; nothing else reports it.
      expect(container.read(failureReporterProvider), isNull);
    });

    test(
      'a created group is not opened when the list does not reload',
      () async {
        await start();
        backend.groups.failFetch = const AppFailure.timeout();

        final result = await notifier().createGroup('Trip', currency: 'EUR');

        expect(result.status, GroupCreateStatus.createdNotOpened);
        expect(result.failure, const AppFailure.timeout());
        // The scope never points at a group this device cannot show.
        expect(backend.groups.activeGroupWrites, isEmpty);
        expect(container.read(groupsProvider).value!.activeGroupId, isNull);
        expect(serverGroupNames(), ['Trip', 'Group g1']);
      },
    );

    test(
      'a create lost on the way is unconfirmed and the list reloads',
      () async {
        await start();
        backend.groups
          ..failCreate = const AppFailure.network()
          ..createBeforeFailing = true;

        final result = await notifier().createGroup(
          'Trip',
          currency: 'INR',
          report: false,
        );

        expect(result.status, GroupCreateStatus.unconfirmed);
        expect(result.created, isFalse);
        expect(result.failure?.key, 'group_unconfirmed');
        // The reloaded list shows what the server has.
        expect(
          container.read(groupsProvider).value!.groups.map((g) => g.name),
          ['Trip', 'Group g1'],
        );
        expect(backend.groups.activeGroupWrites, isEmpty);
      },
    );

    test('a refused create is a failure and creates nothing', () async {
      await start();
      backend.groups.failCreate = const AppFailure.validation(
        key: 'invalid_currency',
      );

      final result = await notifier().createGroup(
        'Trip',
        currency: 'INR',
        report: false,
      );

      expect(result.status, GroupCreateStatus.failed);
      expect(result.failure?.key, 'invalid_currency');
      expect(serverGroupNames(), ['Group g1']);
    });

    test('a create that opens the group succeeds', () async {
      await start();
      final result = await notifier().createGroup('Trip', currency: 'INR');
      expect(result.status, GroupCreateStatus.opened);
      expect(container.read(activeGroupProvider)?.name, 'Trip');
    });
  });

  group('leave and delete', () {
    test(
      'a delete whose reload fails still succeeds and drops the group',
      () async {
        await start(activeGroupId: 'g1');
        expect(container.read(activeGroupProvider)?.id, 'g1');
        backend.groups.failFetch = const AppFailure.network();

        final failure = await notifier().deleteGroup('g1');

        expect(failure, isNull);
        expect(backend.groups.calls, ['delete:g1']);
        final state = container.read(groupsProvider).value!;
        expect(state.groups, isEmpty);
        expect(state.activeGroupId, isNull);
        expect(container.read(userProfileProvider)?.activeGroupId, isNull);
        expect(container.read(failureReporterProvider), isNull);
      },
    );

    test('a leave whose profile reload fails still succeeds', () async {
      await start(activeGroupId: 'g1');
      backend.profiles.failFetch = const AppFailure.timeout();

      final failure = await notifier().leaveGroup('g1');

      expect(failure, isNull);
      expect(backend.groups.calls, ['leave:g1']);
      expect(container.read(groupsProvider).value!.groups, isEmpty);
      expect(container.read(activeGroupProvider), isNull);
    });

    test('a refused leave is reported and keeps the group', () async {
      await start(activeGroupId: 'g1');
      backend.groups.unsettled.add('A');

      final failure = await notifier().leaveGroup('g1');

      expect(failure, const AppFailure.business('outstanding_balance'));
      expect(container.read(activeGroupProvider)?.id, 'g1');
      expect(
        container.read(failureReporterProvider)?.failure,
        const AppFailure.business('outstanding_balance'),
      );
    });
  });
}
