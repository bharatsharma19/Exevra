import 'dart:async';

import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/errors/failure_messages.dart';
import 'package:expense_manager/core/widgets/widgets.dart';
import 'package:expense_manager/data/repositories/expense_repository.dart';
import 'package:expense_manager/features/expenses/expense_date_filter.dart';
import 'package:expense_manager/features/expenses/screens/add_edit_expense_sheet.dart';
import 'package:expense_manager/features/expenses/screens/expenses_screen.dart';
import 'package:expense_manager/models/expense.dart';
import 'package:expense_manager/models/group.dart';
import 'package:expense_manager/providers/data_revision.dart';
import 'package:expense_manager/providers/expense_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/expense_group_harness.dart';
import '../support/fakes.dart';

Future<(TestBackend, ProviderContainer)> _pump(
  WidgetTester tester, {
  List<Expense> rows = const [],
  Group? group,
  AppFailure? failReads,
  void Function(TestBackend backend)? setUp,
  ThemeMode mode = ThemeMode.light,
  double width = 360,
  double textScale = 1,
  bool settle = true,
}) async {
  setPhoneSize(tester, width: width);

  final backend = TestBackend(signedInAs: 'u1');
  backend.profiles.profiles['u1'] = profileOf('u1', activeGroupId: group?.id);
  if (group != null) backend.groups.groupsByUser['u1'] = [group];
  backend.expenses.rows.addAll(rows);
  backend.expenses.failReads = failReads;
  setUp?.call(backend);
  final container = await backend.container();
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: themedApp(
        home: const ExpensesScreen(),
        mode: mode,
        textScale: textScale,
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return (backend, container);
}

List<Expense> _many(int count, {DateTime? from}) => [
  for (var i = 0; i < count; i++)
    expenseOf(
      'p${i.toString().padLeft(2, '0')}',
      userId: 'u1',
      title: 'Expense ${i.toString().padLeft(2, '0')}',
      spentAt: (from ?? DateTime.utc(2026, 1, 1)).add(Duration(hours: i)),
    ),
];

Future<void> _openMenu(WidgetTester tester, String title) async {
  await tester.tap(find.byTooltip('Actions for $title'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in themeModes) {
    testWidgets('a list meets contrast and tap-target guidelines ($mode)', (
      tester,
    ) async {
      await _pump(tester, rows: _many(3), mode: mode);
      expect(find.text('Expense 02'), findsOneWidget);
      await expectAccessibleScreen(tester);
    });

    testWidgets('the empty state meets the guidelines ($mode)', (tester) async {
      await _pump(tester, mode: mode);
      expect(find.byKey(const Key('expenses-empty-new')), findsOneWidget);
      await expectAccessibleScreen(tester);
    });

    testWidgets('fits 320dp at 200% text ($mode)', (tester) async {
      final group = groupOf('g1', adminId: 'u1');
      await _pump(
        tester,
        mode: mode,
        width: 320,
        textScale: 2,
        group: group,
        rows: [
          expenseOf(
            'long',
            userId: 'u1',
            groupId: 'g1',
            title: 'A very long expense title for a weekend trip to the hills',
          ),
          ..._many(2),
        ],
        // The long row is locked, so its reason line must fit too.
        setUp: (b) {
          b.groups.membersByGroup['g1'] = [memberOf('u1')];
          b.expenses.participants['long'] = ['u1', 'u-left'];
        },
      );
      expectNoOverflow(tester);
      expect(find.byKey(const Key('expense-locked')), findsOneWidget);
    });
  }

  testWidgets('shows skeletons while the first page loads', (tester) async {
    final page = Completer<ExpensePage>();
    final (backend, _) = await _pump(
      tester,
      settle: false,
      setUp: (b) => b.expenses.heldFetches.add(page),
    );
    await tester.pump();
    expect(find.byType(SkeletonList), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    page.complete(const ExpensePage([], null));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('expenses-empty-new')), findsOneWidget);
    expect(backend.expenses.fetchCalls, 1);
  });

  testWidgets('loads the next page at the end of the list', (tester) async {
    final (backend, _) = await _pump(tester, rows: _many(45));

    expect(find.text('Expense 44'), findsOneWidget);
    expect(find.text('Expense 00'), findsNothing);
    expect(backend.expenses.fetchCalls, 1);

    await tester.scrollUntilVisible(
      find.text('Expense 00'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(find.text('Expense 00'), findsOneWidget);
    expect(backend.expenses.fetchCalls, 2);
  });

  testWidgets('pull to refresh reloads the list', (tester) async {
    final (backend, _) = await _pump(tester, rows: _many(2));
    expect(backend.expenses.fetchCalls, 1);

    await tester.fling(find.text('Expense 01'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(backend.expenses.fetchCalls, 2);
  });

  testWidgets('a new user sees a call to add the first expense', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byKey(const Key('expenses-empty-new')), findsOneWidget);
    expect(find.text('No expenses yet'), findsOneWidget);
    await tester.tap(find.text('Add your first expense'));
    await tester.pumpAndSettle();
    expect(find.byType(AddEditExpenseSheet), findsOneWidget);
  });

  testWidgets('no results for a search offers to clear it', (tester) async {
    final (_, container) = await _pump(tester, rows: _many(3));

    container.read(expenseFilterProvider.notifier).setSearch('zzz');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('expenses-empty-filtered')), findsOneWidget);
    expect(find.byKey(const Key('expenses-empty-new')), findsNothing);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('Expense 02'), findsOneWidget);
  });

  testWidgets('a category filter narrows the list and counts the results', (
    tester,
  ) async {
    await _pump(
      tester,
      rows: [
        expenseOf('a', userId: 'u1', title: 'Lunch'),
        expenseOf(
          'b',
          userId: 'u1',
          title: 'Bus',
        ).copyWith(category: 'Transport'),
      ],
    );

    final chip = find.widgetWithText(FilterChip, 'Transport');
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.text('Bus'), findsOneWidget);
    expect(find.text('Lunch'), findsNothing);
    expect(find.text('1 expense found'), findsOneWidget);

    // Tapping it again shows every category.
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.text('Lunch'), findsOneWidget);
  });

  testWidgets('a date filter with no match is told apart from a new user', (
    tester,
  ) async {
    final now = DateTime.now();
    final (_, container) = await _pump(
      tester,
      rows: _many(2, from: DateTime(now.year - 2).toUtc()),
    );

    await tester.tap(find.byKey(const Key('expenses-date-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('expenses-date-last7Days')));
    await tester.pumpAndSettle();

    expect(
      container.read(expenseDatePresetProvider),
      ExpenseDatePreset.last7Days,
    );
    expect(find.byKey(const Key('expenses-empty-filtered')), findsOneWidget);
    expect(find.text('Last 7 days'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(container.read(expenseDatePresetProvider), ExpenseDatePreset.any);
    expect(find.text('Expense 01'), findsOneWidget);
  });

  testWidgets('a failed load shows friendly copy with Retry', (tester) async {
    final (backend, _) = await _pump(
      tester,
      rows: _many(2),
      failReads: const AppFailure.offline(),
    );

    expect(find.text("Couldn't load your expenses"), findsOneWidget);
    expect(
      find.text(friendlyMessage(const AppFailure.offline())),
      findsOneWidget,
    );
    backend.expenses.failReads = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Expense 01'), findsOneWidget);
  });

  testWidgets('delete asks first and Undo restores the expense', (
    tester,
  ) async {
    final (backend, _) = await _pump(tester, rows: _many(1));

    await _openMenu(tester, 'Expense 00');
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(find.text('Delete expense?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(backend.expenses.rows, isEmpty);
    expect(find.byKey(const Key('expenses-empty-new')), findsOneWidget);
    expect(find.text('Deleted "Expense 00"'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(backend.expenses.rows.single.title, 'Expense 00');
    expect(find.text('Expense 00'), findsOneWidget);
  });

  testWidgets('cancelling the delete keeps the expense', (tester) async {
    final (backend, _) = await _pump(tester, rows: _many(1));

    await _openMenu(tester, 'Expense 00');
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(backend.expenses.rows, hasLength(1));
    expect(backend.expenses.deleted, isEmpty);
  });

  testWidgets('group expenses say who paid', (tester) async {
    final group = groupOf('g1', adminId: 'u9', role: GroupRole.member);
    await _pump(
      tester,
      group: group,
      rows: [
        expenseOf('mine', userId: 'u1', groupId: 'g1', title: 'Mine'),
        expenseOf('solo', userId: 'u1', title: 'Solo'),
      ],
    );

    expect(find.text('You paid'), findsOneWidget);
    // A personal expense among group ones is tagged.
    expect(find.text('Personal'), findsWidgets);
  });

  testWidgets("others' group expenses show no edit or delete to a member", (
    tester,
  ) async {
    final group = groupOf('g1', adminId: 'u9', role: GroupRole.member);
    await _pump(
      tester,
      group: group,
      rows: [
        expenseOf('mine', userId: 'u1', groupId: 'g1', title: 'Mine'),
        expenseOf(
          'theirs',
          userId: 'u2',
          groupId: 'g1',
          title: 'Theirs',
          spentAt: DateTime.utc(2026, 10, 1),
        ),
      ],
    );

    expect(find.text('Mine'), findsOneWidget);
    expect(find.text('Theirs'), findsOneWidget);
    // Only the payer's own row has actions.
    expect(find.byTooltip('Actions for Mine'), findsOneWidget);
    expect(find.byTooltip('Actions for Theirs'), findsNothing);

    await tester.tap(find.text('Theirs'));
    await tester.pumpAndSettle();
    expect(find.byType(AddEditExpenseSheet), findsNothing);
    expect(
      find.text('Only the person who paid can edit this expense.'),
      findsOneWidget,
    );
  });

  testWidgets("the group admin can delete others' expenses without Undo", (
    tester,
  ) async {
    final group = groupOf('g1', adminId: 'u1');
    final (backend, _) = await _pump(
      tester,
      group: group,
      rows: [expenseOf('theirs', userId: 'u2', groupId: 'g1', title: 'Theirs')],
    );

    await _openMenu(tester, 'Theirs');
    expect(find.text('Edit'), findsNothing);
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(find.textContaining("can't be undone"), findsOneWidget);
    expect(find.textContaining('for everyone in the group'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(backend.expenses.rows, isEmpty);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('a locked group expense shows the lock and cannot be deleted', (
    tester,
  ) async {
    final group = groupOf('g1', adminId: 'u1');
    final (backend, _) = await _pump(
      tester,
      group: group,
      rows: [expenseOf('ge', userId: 'u1', groupId: 'g1', title: 'Shared')],
      setUp: (b) {
        b.groups.membersByGroup['g1'] = [memberOf('u1')];
        b.expenses.participants['ge'] = ['u1', 'u-left'];
      },
    );

    // The row says why, with a lock, before any menu is opened.
    final row = find.byKey(const Key('expense-locked'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(
        of: row,
        matching: find.byIcon(Icons.lock_outline_rounded),
      ),
      findsOneWidget,
    );
    expect(find.text('Locked: someone in it left the group'), findsOneWidget);

    await _openMenu(tester, 'Shared');
    final item = tester.widget<PopupMenuItem<Object?>>(
      find.ancestor(
        of: find.text('Delete').last,
        matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
      ),
    );
    expect(item.enabled, isFalse);
    // Edit stays: the title, category, date and note can still change.
    expect(find.text('Edit'), findsOneWidget);
    await tester.tap(find.text('Delete').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Delete expense?'), findsNothing);
    expect(backend.expenses.rows, hasLength(1));
    expect(backend.expenses.deleted, isEmpty);
  });

  testWidgets('the rows share their lock-check reads', (tester) async {
    final group = groupOf('g1', adminId: 'u1');
    final ids = [for (var i = 0; i < 6; i++) 'g$i'];
    final (backend, _) = await _pump(
      tester,
      group: group,
      rows: [
        for (final (i, id) in ids.indexed)
          expenseOf(
            id,
            userId: 'u1',
            groupId: 'g1',
            title: 'Shared $i',
            spentAt: DateTime.utc(2026, 11, 1, i),
          ),
      ],
      setUp: (b) {
        b.groups.membersByGroup['g1'] = [memberOf('u1')];
        b.expenses.participants['g3'] = ['u1', 'u-left'];
      },
    );

    expect(find.byKey(const Key('expense-locked')), findsOneWidget);
    // One participants read for the rows of the frame, not one per row.
    expect(backend.expenses.participantFetches, 1);
    final asked = backend.expenses.participantBatches.single;
    expect(asked, contains('g3'));
    expect(asked.length, greaterThan(1));
    expect(asked.toSet(), hasLength(asked.length));
    // The members are read once for the checks (and once for the screen),
    // not once per row.
    expect(
      backend.groups.memberFetches.where((g) => g == 'g1').length,
      lessThanOrEqualTo(2),
    );
  });

  testWidgets('an expense that locks after the list loaded is not deleted', (
    tester,
  ) async {
    final group = groupOf('g1', adminId: 'u1');
    final (backend, container) = await _pump(
      tester,
      group: group,
      rows: [expenseOf('ge', userId: 'u1', groupId: 'g1', title: 'Shared')],
      setUp: (b) {
        b.groups.membersByGroup['g1'] = [memberOf('u1'), memberOf('u2')];
        b.expenses.participants['ge'] = ['u1', 'u2'];
      },
    );
    expect(find.byKey(const Key('expense-locked')), findsNothing);

    // u2 leaves (the members change is pushed) while the row still shows
    // the earlier answer.
    final hold = Completer<void>();
    backend.groups.gate.hold = hold;
    backend.groups.membersByGroup['g1'] = [memberOf('u1')];
    container.read(dataRevisionProvider.notifier).bump(DataKind.members);
    await tester.pump();

    await _openMenu(tester, 'Shared');
    await tester.tap(find.text('Delete').last);
    await tester.pump();
    hold.complete();
    backend.groups.gate.hold = null;
    await tester.pumpAndSettle();

    expect(find.text('Delete expense?'), findsNothing);
    expect(find.text('This expense is locked'), findsOneWidget);
    expect(
      find.text(friendlyMessageForKey('expense_locked_member_left')),
      findsOneWidget,
    );
    expect(backend.expenses.deleted, isEmpty);
  });

  testWidgets('date headers come from the app strings', (tester) async {
    final now = DateTime.now();
    await _pump(
      tester,
      rows: [
        expenseOf('t', userId: 'u1', title: 'Lunch', spentAt: now),
        expenseOf(
          'y',
          userId: 'u1',
          title: 'Taxi',
          spentAt: now.subtract(const Duration(days: 1)),
        ),
      ],
    );

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
  });
}
