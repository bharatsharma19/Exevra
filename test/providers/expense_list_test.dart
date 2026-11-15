import 'dart:async';

import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/data/repositories/expense_repository.dart';
import 'package:expense_manager/models/expense.dart';
import 'package:expense_manager/models/group.dart';
import 'package:expense_manager/models/money.dart';
import 'package:expense_manager/providers/data_revision.dart';
import 'package:expense_manager/providers/expense_provider.dart';
import 'package:expense_manager/providers/failure_reporter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  // Haptics and other platform calls need the test binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  const personal = ExpenseListKey(
    'u1',
    ExpenseQuery(scope: ExpenseScope.personal()),
  );

  late TestBackend backend;
  late ProviderContainer container;

  Future<ExpenseListNotifier> load([ExpenseListKey key = personal]) async {
    container.listen(expenseListProvider(key), (_, _) {});
    await container.read(expenseListProvider(key).future);
    return container.read(expenseListProvider(key).notifier);
  }

  List<String> ids([ExpenseListKey key = personal]) => [
    for (final e in container.read(expenseListProvider(key)).value!.items) e.id,
  ];

  setUp(() async {
    backend = TestBackend(signedInAs: 'u1');
    backend.expenses.rows.addAll([
      expenseOf('e2', userId: 'u1', spentAt: DateTime.utc(2026, 11, 2)),
      expenseOf('e1', userId: 'u1', spentAt: DateTime.utc(2026, 11, 1)),
      expenseOf('other', userId: 'u2'),
    ]);
    container = await backend.container();
    addTearDown(container.dispose);
  });

  ExpenseDraft draft({DateTime? at}) => ExpenseDraft(
    title: 'Coffee',
    amount: Money(25000, 'INR'),
    category: 'Food',
    spentAt: at ?? DateTime.utc(2026, 11, 3),
  );

  group('loading', () {
    test('shows only the user\'s rows, newest first', () async {
      await load();
      expect(ids(), ['e2', 'e1']);
    });

    test('a list of another user is empty', () async {
      const foreign = ExpenseListKey(
        'u2',
        ExpenseQuery(scope: ExpenseScope.personal()),
      );
      await load(foreign);
      expect(ids(foreign), isEmpty);
    });

    test('concurrent reloads keep only the latest result', () async {
      final notifier = await load();
      final first = Completer<ExpensePage>();
      final second = Completer<ExpensePage>();
      backend.expenses.heldFetches.addAll([first, second]);

      final a = notifier.reload();
      final b = notifier.reload();
      second.complete(ExpensePage([expenseOf('new', userId: 'u1')], null));
      await b;
      first.complete(ExpensePage([expenseOf('stale', userId: 'u1')], null));
      await a;

      expect(ids(), ['new']);
    });

    test('a failed first page is an error the screen can retry', () async {
      backend.expenses.failReads = const AppFailure.offline();
      container.listen(expenseListProvider(personal), (_, _) {});
      await expectLater(
        container.read(expenseListProvider(personal).future),
        throwsA(isA<OfflineFailure>()),
      );
      backend.expenses.failReads = null;
      final failure = await container
          .read(expenseListProvider(personal).notifier)
          .reload();
      expect(failure, isNull);
      expect(ids(), ['e2', 'e1']);
    });
  });

  group('optimistic writes', () {
    test('add shows the row at once and keeps the server row', () async {
      final notifier = await load();
      final pending = notifier.add(draft());
      expect(ids().first, startsWith(Expense.localIdPrefix));
      expect(
        container
            .read(expenseListProvider(personal))
            .value!
            .items
            .first
            .isSyncing,
        isTrue,
      );
      expect(await pending, isNull);
      expect(ids(), ['srv-1', 'e2', 'e1']);
    });

    test('a successful write tells other lists to reload', () async {
      final notifier = await load();
      final before = container.read(dataRevisionProvider).expenses;
      await notifier.add(draft());
      expect(container.read(dataRevisionProvider).expenses, before + 1);
    });

    test('a failed add rolls back and exposes the failure', () async {
      final notifier = await load();
      backend.expenses.failWrites = const AppFailure.permissionDenied();

      final failure = await notifier.add(draft());

      expect(failure, isA<PermissionDeniedFailure>());
      expect(ids(), ['e2', 'e1']);
      expect(
        container.read(failureReporterProvider)?.failure,
        isA<PermissionDeniedFailure>(),
      );
    });

    test('an invalid draft is rejected before any request', () async {
      final notifier = await load();
      final failure = await notifier.add(
        ExpenseDraft(
          title: '  ',
          amount: Money(100, 'INR'),
          category: 'Food',
          spentAt: DateTime.utc(2026),
        ),
      );
      expect(failure, isA<ValidationFailure>());
      expect(ids(), ['e2', 'e1']);
    });

    test('a failed edit restores the original row', () async {
      final notifier = await load();
      final original = container
          .read(expenseListProvider(personal))
          .value!
          .items
          .last;
      backend.expenses.failWrites = const AppFailure.network();

      final failure = await notifier.edit(
        original.copyWith(title: 'Changed', note: 'x'),
      );

      expect(failure, isA<NetworkFailure>());
      final items = container.read(expenseListProvider(personal)).value!.items;
      expect(items.map((e) => e.id), ['e2', 'e1']);
      expect(items.last, original);
      expect(items.last.isSyncing, isFalse);
    });

    test('an edit that moves the date re-sorts the list', () async {
      final notifier = await load();
      final oldest = container
          .read(expenseListProvider(personal))
          .value!
          .items
          .last;
      expect(
        await notifier.edit(oldest.copyWith(spentAt: DateTime.utc(2026, 12))),
        isNull,
      );
      expect(ids(), ['e1', 'e2']);
    });

    test('a failed delete puts the row back in place', () async {
      final notifier = await load();
      final first = container
          .read(expenseListProvider(personal))
          .value!
          .items
          .first;
      backend.expenses.failWrites = const AppFailure.permissionDenied();

      final pending = notifier.remove(first);
      expect(ids(), ['e1']);
      expect(await pending, isA<PermissionDeniedFailure>());
      expect(ids(), ['e2', 'e1']);
    });

    test('a successful delete removes the row', () async {
      final notifier = await load();
      final first = container
          .read(expenseListProvider(personal))
          .value!
          .items
          .first;
      expect(await notifier.remove(first), isNull);
      expect(ids(), ['e1']);
      expect(backend.expenses.rows.map((e) => e.id), isNot(contains('e2')));
    });
  });

  group('matching', () {
    test('mirrors the server scope and filters', () {
      final mine = expenseOf('a', userId: 'u1');
      final groupRow = expenseOf('b', userId: 'u2', groupId: 'g1');
      const both = ExpenseListKey(
        'u1',
        ExpenseQuery(scope: ExpenseScope.personalAndGroup('g1')),
      );
      const food = ExpenseListKey(
        'u1',
        ExpenseQuery(scope: ExpenseScope.personal(), category: 'Food'),
      );
      const search = ExpenseListKey(
        'u1',
        ExpenseQuery(scope: ExpenseScope.personal(), search: 'LUN'),
      );
      expect(ExpenseListNotifier.matches(personal, mine), isTrue);
      expect(ExpenseListNotifier.matches(personal, groupRow), isFalse);
      expect(ExpenseListNotifier.matches(both, groupRow), isTrue);
      expect(ExpenseListNotifier.matches(food, mine), isTrue);
      expect(ExpenseListNotifier.matches(search, mine), isTrue);
    });

    test('scope follows the active group and the type filter', () {
      final group = groupOf('g1', adminId: 'u1');
      expect(
        scopeFor(null, ExpenseTypeFilter.group),
        const ExpenseScope.personal(),
      );
      expect(
        scopeFor(group, ExpenseTypeFilter.all),
        const ExpenseScope.personalAndGroup('g1'),
      );
      expect(
        scopeFor(group, ExpenseTypeFilter.group),
        const ExpenseScope.group('g1'),
      );
      final pending = groupOf(
        'g2',
        adminId: 'u9',
        role: GroupRole.viewer,
        status: MemberStatus.pending,
      );
      expect(
        scopeFor(pending, ExpenseTypeFilter.all),
        const ExpenseScope.personal(),
      );
    });
  });

  group('convert', () {
    test('moves a personal expense into a group in one step', () async {
      backend.groups.groupsByUser['u1'] = [groupOf('g1', adminId: 'u1')];
      final notifier = await load();
      final original = backend.expenses.rows.firstWhere((e) => e.id == 'e2');

      final failure = await notifier.convert(
        original,
        ExpenseDraft.fromExpense(original, groupId: 'g1'),
      );

      expect(failure, isNull);
      expect(backend.expenses.rows.where((e) => e.id == 'e2'), isEmpty);
      final moved = backend.expenses.rows.where((e) => e.groupId == 'g1');
      expect(moved, hasLength(1));
      expect(moved.single.amount, original.amount);
      // The personal list no longer shows it.
      expect(ids(), ['e1']);
    });

    test('when the original cannot be removed the copy is undone', () async {
      final notifier = await load();
      final original = backend.expenses.rows.firstWhere((e) => e.id == 'e2');
      backend.expenses.failDeleteIds.add('e2');

      final failure = await notifier.convert(
        original,
        ExpenseDraft.fromExpense(original, groupId: 'g1'),
      );

      expect(failure, isA<PermissionDeniedFailure>());
      expect(backend.expenses.rows.where((e) => e.groupId == 'g1'), isEmpty);
      expect(backend.expenses.rows.where((e) => e.id == 'e2'), hasLength(1));
      expect(ids(), ['e2', 'e1']);
      expect(container.read(failureReporterProvider)?.failure, failure);
    });

    test('report: false returns the failure without reporting it', () async {
      final notifier = await load();
      backend.expenses.failWrites = const AppFailure.network();
      final failure = await notifier.add(draft(), report: false);
      expect(failure, const AppFailure.network(key: 'expense_unconfirmed'));
      expect(container.read(failureReporterProvider), isNull);
      expect(ids(), ['e2', 'e1']);
    });
  });

  group('writes racing a reload', () {
    test('a delete confirmed during a reload stays deleted', () async {
      final notifier = await load();
      final held = Completer<ExpensePage>();
      backend.expenses.heldFetches.add(held);
      final e2 = backend.expenses.rows.firstWhere((e) => e.id == 'e2');
      final e1 = backend.expenses.rows.firstWhere((e) => e.id == 'e1');

      final reloading = notifier.reload();
      expect(await notifier.remove(e2), isNull);
      // The page was read before the delete reached the server.
      held.complete(ExpensePage([e2, e1], null));
      await reloading;

      expect(ids(), ['e1']);
    });

    test('an edit confirmed during a reload is kept', () async {
      final notifier = await load();
      final held = Completer<ExpensePage>();
      backend.expenses.heldFetches.add(held);
      final e2 = backend.expenses.rows.firstWhere((e) => e.id == 'e2');
      final e1 = backend.expenses.rows.firstWhere((e) => e.id == 'e1');

      final reloading = notifier.reload();
      expect(await notifier.edit(e1.copyWith(title: 'Changed')), isNull);
      held.complete(ExpensePage([e2, e1], null));
      await reloading;

      final items = container.read(expenseListProvider(personal)).value!.items;
      expect(items.map((e) => e.id), ['e2', 'e1']);
      expect(items.last.title, 'Changed');
    });

    test('a page that already has the new row does not duplicate it', () async {
      final notifier = await load();
      final release = Completer<void>();
      backend.expenses.holdWrites = release;
      final held = Completer<ExpensePage>();
      backend.expenses.heldFetches.add(held);
      final e2 = backend.expenses.rows.firstWhere((e) => e.id == 'e2');
      final e1 = backend.expenses.rows.firstWhere((e) => e.id == 'e1');

      final adding = notifier.add(draft());
      final reloading = notifier.reload();
      // The insert reached the server before its response came back.
      final early = expenseOf(
        'srv-1',
        userId: 'u1',
        spentAt: DateTime.utc(2026, 11, 3),
      );
      held.complete(ExpensePage([early, e2, e1], null));
      await reloading;
      release.complete();
      expect(await adding, isNull);

      expect(ids(), ['srv-1', 'e2', 'e1']);
    });

    test(
      'a realtime reload before the add is answered shows it once',
      () async {
        final notifier = await load();
        final answer = Completer<void>();
        backend.expenses.holdCreateAnswer = answer;

        final adding = notifier.add(draft());
        await settle();
        // The row is on the server; a realtime change reloads the list
        // before the create's answer arrives.
        expect(
          backend.expenses.rows.where((e) => e.title == 'Coffee'),
          hasLength(1),
        );
        container.read(dataRevisionProvider.notifier).bump(DataKind.expenses);
        await settle();

        final during = container.read(expenseListProvider(personal)).value!;
        expect(during.items.where((e) => e.title == 'Coffee'), hasLength(1));
        expect(during.items, hasLength(3));

        answer.complete();
        expect(await adding, isNull);
        await settle();
        expect(ids(), ['srv-1', 'e2', 'e1']);
      },
    );

    test('a pending edit replaces the server copy of the same row', () async {
      final notifier = await load();
      final release = Completer<void>();
      backend.expenses.holdWrites = release;
      final e1 = backend.expenses.rows.firstWhere((e) => e.id == 'e1');

      final editing = notifier.edit(e1.copyWith(title: 'Changed'));
      await notifier.reload();

      final during = container.read(expenseListProvider(personal)).value!;
      expect(during.items.map((e) => e.id), ['e2', 'e1']);
      expect(during.items.last.title, 'Changed');
      release.complete();
      expect(await editing, isNull);
      expect(ids(), ['e2', 'e1']);
    });

    test(
      'an add that fails in transit reloads instead of inviting a retry',
      () async {
        final notifier = await load();
        final before = backend.expenses.fetchCalls;
        backend.expenses.failWrites = const AppFailure.timeout();

        final failure = await notifier.add(draft(), report: false);
        await settle();

        expect(failure, const AppFailure.network(key: 'expense_unconfirmed'));
        expect(backend.expenses.fetchCalls, greaterThan(before));
      },
    );
  });

  group('paging', () {
    test('loads further pages after the cursor without duplicates', () async {
      backend.expenses.rows.clear();
      for (var i = 0; i < 70; i++) {
        backend.expenses.rows.add(
          expenseOf(
            'p${i.toString().padLeft(2, '0')}',
            userId: 'u1',
            spentAt: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
          ),
        );
      }
      final notifier = await load();
      var state = container.read(expenseListProvider(personal)).value!;
      expect(state.items, hasLength(ExpenseListNotifier.pageSize));
      expect(state.hasMore, isTrue);

      await notifier.loadMore();
      await notifier.loadMore();
      state = container.read(expenseListProvider(personal)).value!;
      expect(state.items, hasLength(70));
      expect(state.hasMore, isFalse);
      expect(state.items.map((e) => e.id).toSet(), hasLength(70));
      expect(state.items.first.id, 'p69');
      expect(state.items.last.id, 'p00');
    });

    test(
      'a reload that fails during "load more" does not leave it stuck',
      () async {
        backend.expenses.rows.clear();
        for (var i = 0; i < 40; i++) {
          backend.expenses.rows.add(
            expenseOf(
              'r${i.toString().padLeft(2, '0')}',
              userId: 'u1',
              spentAt: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
            ),
          );
        }
        final notifier = await load();
        final held = Completer<ExpensePage>();
        backend.expenses.heldFetches.add(held);
        final more = notifier.loadMore();
        expect(
          container.read(expenseListProvider(personal)).value!.isLoadingMore,
          isTrue,
        );

        backend.expenses.failReads = const AppFailure.offline();
        expect(await notifier.reload(), isA<OfflineFailure>());
        held.complete(const ExpensePage([], null));
        await more;

        var state = container.read(expenseListProvider(personal)).value!;
        expect(state.isLoadingMore, isFalse);
        expect(state.items, hasLength(30));

        backend.expenses.failReads = null;
        await notifier.loadMore();
        state = container.read(expenseListProvider(personal)).value!;
        expect(state.items, hasLength(40));
        expect(state.items.map((e) => e.id).toSet(), hasLength(40));
      },
    );

    test('a failed page keeps the rows and offers retry', () async {
      backend.expenses.rows.clear();
      for (var i = 0; i < 40; i++) {
        backend.expenses.rows.add(
          expenseOf(
            'q${i.toString().padLeft(2, '0')}',
            userId: 'u1',
            spentAt: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
          ),
        );
      }
      final notifier = await load();
      backend.expenses.failReads = const AppFailure.offline();
      await notifier.loadMore();
      var state = container.read(expenseListProvider(personal)).value!;
      expect(state.loadMoreFailure, const AppFailure.offline());
      expect(state.items, hasLength(30));

      backend.expenses.failReads = null;
      await notifier.loadMore();
      state = container.read(expenseListProvider(personal)).value!;
      expect(state.loadMoreFailure, isNull);
      expect(state.items, hasLength(40));
    });
  });
}
