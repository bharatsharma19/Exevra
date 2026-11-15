import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/errors/failure_messages.dart';
import 'package:expense_manager/features/expenses/screens/add_edit_expense_sheet.dart';
import 'package:expense_manager/features/expenses/screens/expenses_screen.dart';
import 'package:expense_manager/models/expense.dart';
import 'package:expense_manager/models/group.dart';
import 'package:expense_manager/providers/expense_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

Future<(TestBackend, ProviderContainer)> _pump(
  WidgetTester tester, {
  List<Expense> rows = const [],
  Group? group,
  AppFailure? failReads,
  void Function(TestBackend backend)? setUp,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

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
      child: const MaterialApp(home: ExpensesScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return (backend, container);
}

List<Expense> _many(int count) => [
  for (var i = 0; i < count; i++)
    expenseOf(
      'p${i.toString().padLeft(2, '0')}',
      userId: 'u1',
      title: 'Expense ${i.toString().padLeft(2, '0')}',
      spentAt: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
    ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  testWidgets('a new user sees a call to add the first expense', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byKey(const Key('expenses-empty-new')), findsOneWidget);
    await tester.tap(find.text('Add your first expense'));
    await tester.pumpAndSettle();
    expect(find.byType(AddEditExpenseSheet), findsOneWidget);
  });

  testWidgets('no results for a filter offers to clear it', (tester) async {
    final (_, container) = await _pump(tester, rows: _many(3));

    container.read(expenseFilterProvider.notifier).setSearch('zzz');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('expenses-empty-filtered')), findsOneWidget);
    expect(find.byKey(const Key('expenses-empty-new')), findsNothing);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('Expense 02'), findsOneWidget);
  });

  testWidgets('a failed load shows friendly copy with Retry', (tester) async {
    final (backend, _) = await _pump(
      tester,
      rows: _many(2),
      failReads: const AppFailure.offline(),
    );

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

    await tester.tap(find.byTooltip('Expense actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(find.text('Delete expense?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(backend.expenses.rows, isEmpty);
    expect(find.byKey(const Key('expenses-empty-new')), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(backend.expenses.rows.single.title, 'Expense 00');
    expect(find.text('Expense 00'), findsOneWidget);
  });

  testWidgets('others\' group expenses show no edit or delete to a member', (
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
    expect(find.byTooltip('Expense actions'), findsOneWidget);
  });

  testWidgets('the group admin can delete others\' expenses without Undo', (
    tester,
  ) async {
    final group = groupOf('g1', adminId: 'u1');
    final (backend, _) = await _pump(
      tester,
      group: group,
      rows: [expenseOf('theirs', userId: 'u2', groupId: 'g1', title: 'Theirs')],
    );

    await tester.tap(find.byTooltip('Expense actions'));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsNothing);
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(backend.expenses.rows, isEmpty);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('a group expense shared with someone who left is not deleted', (
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

    await tester.tap(find.byTooltip('Expense actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(find.text('Delete expense?'), findsNothing);
    expect(
      find.text(
        "This expense can't be changed because someone in it has left the "
        'group.',
      ),
      findsOneWidget,
    );
    expect(backend.expenses.rows, hasLength(1));
    expect(backend.expenses.deleted, isEmpty);
  });
}
