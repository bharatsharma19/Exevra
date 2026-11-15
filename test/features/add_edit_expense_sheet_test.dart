import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/errors/failure_messages.dart';
import 'package:expense_manager/features/expenses/screens/add_edit_expense_sheet.dart';
import 'package:expense_manager/models/expense.dart';
import 'package:expense_manager/models/group.dart';
import 'package:expense_manager/models/money.dart';
import 'package:expense_manager/providers/failure_reporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Opens the sheet from a button so dismissal goes through the route.
class _Host extends StatelessWidget {
  const _Host({this.expense});

  final Expense? expense;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => AddEditExpenseSheet.show(context, expense: expense),
          child: const Text('open'),
        ),
      ),
    );
  }
}

Future<(TestBackend, ProviderContainer)> _pump(
  WidgetTester tester, {
  GroupRole role = GroupRole.admin,
  bool withGroup = true,
  Expense? expense,
  List<Expense> rows = const [],
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final backend = TestBackend(signedInAs: 'u1');
  backend.profiles.profiles['u1'] = profileOf(
    'u1',
    activeGroupId: withGroup ? 'g1' : null,
  );
  if (withGroup) {
    backend.groups.groupsByUser['u1'] = [
      groupOf(
        'g1',
        adminId: role == GroupRole.admin ? 'u1' : 'u9',
        role: role,
        currency: 'EUR',
      ),
    ];
  }
  backend.expenses.rows.addAll(rows);
  final container = await backend.container();
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: _Host(expense: expense)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (backend, container);
}

Future<void> _save(WidgetTester tester) async {
  final save = find.byKey(const Key('expense-save'));
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('parses the amount in the group currency and saves it', (
    tester,
  ) async {
    final (backend, _) = await _pump(tester);

    // A group expense is locked to the group currency.
    expect(find.byKey(const Key('expense-currency-locked')), findsOneWidget);
    expect(find.text('EUR'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('expense-amount')), '1,250.5');
    await tester.enterText(find.byKey(const Key('expense-title')), 'Dinner');
    await _save(tester);

    expect(find.byType(AddEditExpenseSheet), findsNothing);
    final saved = backend.expenses.rows.single;
    expect(saved.amount, Money(125050, 'EUR'));
    expect(saved.groupId, 'g1');
    expect(saved.title, 'Dinner');
  });

  testWidgets('rejects too many decimals inline and keeps the sheet', (
    tester,
  ) async {
    final (backend, _) = await _pump(tester);

    await tester.enterText(find.byKey(const Key('expense-amount')), '12.345');
    await tester.enterText(find.byKey(const Key('expense-title')), 'Taxi');
    await _save(tester);

    expect(
      find.text(friendlyMessageForKey('amount_too_many_decimals')),
      findsOneWidget,
    );
    expect(find.byType(AddEditExpenseSheet), findsOneWidget);
    expect(backend.expenses.rows, isEmpty);
  });

  testWidgets('personal expenses use a chosen currency', (tester) async {
    final (backend, _) = await _pump(tester, withGroup: false);

    expect(find.byKey(const Key('expense-currency')), findsOneWidget);
    await tester.tap(find.byKey(const Key('expense-currency')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JPY').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('expense-amount')), '1200');
    await tester.enterText(find.byKey(const Key('expense-title')), 'Ramen');
    await _save(tester);

    final saved = backend.expenses.rows.single;
    expect(saved.amount, Money(1200, 'JPY'));
    expect(saved.isPersonal, isTrue);
  });

  testWidgets('clearing the note saves it as empty', (tester) async {
    final original = expenseOf(
      'e1',
      userId: 'u1',
    ).copyWith(note: 'Old note', amount: Money(1000, 'EUR'));
    final (backend, _) = await _pump(
      tester,
      withGroup: false,
      expense: original,
      rows: [original],
    );

    await tester.tap(find.byTooltip('Clear note'));
    await tester.pump();
    await _save(tester);

    final saved = backend.expenses.rows.single;
    expect(saved.id, 'e1');
    expect(saved.note, isNull);
    expect(saved.toUpdateJson()['note'], isNull);
  });

  testWidgets('moves a personal expense into the active group', (tester) async {
    final original = expenseOf(
      'e1',
      userId: 'u1',
    ).copyWith(amount: Money(4000, 'EUR'));
    final (backend, _) = await _pump(
      tester,
      expense: original,
      rows: [original],
    );

    await tester.tap(find.text('Group Expense'));
    await tester.pump();
    expect(find.byKey(const Key('expense-currency-locked')), findsOneWidget);
    await _save(tester);

    expect(find.byType(AddEditExpenseSheet), findsNothing);
    final rows = backend.expenses.rows;
    expect(rows.where((e) => e.id == 'e1'), isEmpty);
    final moved = rows.single;
    expect(moved.groupId, 'g1');
    expect(moved.amount, Money(4000, 'EUR'));
    expect(moved.title, original.title);
  });

  testWidgets('asks before discarding unsaved changes', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byKey(const Key('expense-title')), 'Draft');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(AddEditExpenseSheet), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);

    // Tapping outside the sheet asks as well.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(AddEditExpenseSheet), findsNothing);
  });

  testWidgets('closes without asking when nothing changed', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(AddEditExpenseSheet), findsNothing);
  });

  testWidgets('a viewer cannot add a group expense and is told why', (
    tester,
  ) async {
    final (backend, _) = await _pump(tester, role: GroupRole.viewer);

    // Starts as personal; Group explains why it is unavailable.
    await tester.tap(find.text('Group Expense'));
    await tester.pump();
    expect(
      find.text(friendlyMessageForKey('viewer_cannot_add')),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('expense-amount')), '50');
    await tester.enterText(find.byKey(const Key('expense-title')), 'Snacks');
    await _save(tester);

    final saved = backend.expenses.rows.single;
    expect(saved.isPersonal, isTrue);
  });

  testWidgets('a server failure is shown in the sheet and rolled back', (
    tester,
  ) async {
    final (backend, container) = await _pump(tester);
    backend.expenses.failWrites = const AppFailure.network();

    await tester.enterText(find.byKey(const Key('expense-amount')), '10');
    await tester.enterText(find.byKey(const Key('expense-title')), 'Coffee');
    await _save(tester);

    expect(find.byKey(const Key('expense-form-error')), findsOneWidget);
    expect(
      find.text(friendlyMessage(const AppFailure.network())),
      findsOneWidget,
    );
    expect(find.byType(AddEditExpenseSheet), findsOneWidget);
    expect(backend.expenses.rows, isEmpty);
    // Shown once, in the sheet, not under the modal barrier.
    expect(container.read(failureReporterProvider), isNull);
  });
}
