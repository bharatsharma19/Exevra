import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/errors/failure_messages.dart';
import 'package:expense_manager/core/widgets/app_snackbar.dart';
import 'package:expense_manager/features/expenses/screens/add_edit_expense_sheet.dart';
import 'package:expense_manager/features/expenses/widgets/expense_form_fields.dart';
import 'package:expense_manager/models/expense.dart';
import 'package:expense_manager/models/group.dart';
import 'package:expense_manager/models/money.dart';
import 'package:expense_manager/providers/failure_reporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/expense_group_harness.dart';
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
  void Function(TestBackend backend)? setUp,
  bool rootMessenger = false,
  ThemeMode mode = ThemeMode.light,
  double width = 360,
  double height = 800,
  double textScale = 1,
}) async {
  setPhoneSize(tester, width: width, height: height);

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
  setUp?.call(backend);
  final container = await backend.container();
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: themedApp(
        messengerKey: rootMessenger ? rootScaffoldMessengerKey : null,
        home: _Host(expense: expense),
        mode: mode,
        textScale: textScale,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (backend, container);
}

/// The Personal or Group segment (a category is also called Personal).
Finder _scope(String label) => find.descendant(
  of: find.byType(ExpenseScopeSelector),
  matching: find.text(label),
);

Future<void> _tapScope(WidgetTester tester, String label) async {
  await tester.ensureVisible(_scope(label));
  await tester.tap(_scope(label));
  await tester.pump();
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

    await tester.ensureVisible(find.byTooltip('Clear note'));
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

    await _tapScope(tester, 'Group');
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

  testWidgets('a move is one server call and Undo moves it back', (
    tester,
  ) async {
    final original = expenseOf(
      'e1',
      userId: 'u1',
    ).copyWith(amount: Money(4000, 'EUR'));
    final (backend, _) = await _pump(
      tester,
      expense: original,
      rows: [original],
      rootMessenger: true,
    );

    await _tapScope(tester, 'Group');
    await _save(tester);

    expect(backend.expenses.moves, [('e1', 'g1')]);
    expect(backend.expenses.deleted, isEmpty);
    final movedId = backend.expenses.rows.single.id;
    expect(find.textContaining('Moved "${original.title}"'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(backend.expenses.moves, [('e1', 'g1'), (movedId, null)]);
    expect(backend.expenses.rows.single.isPersonal, isTrue);
    rootScaffoldMessengerKey.currentState?.clearSnackBars();
  });

  group('locked group expense', () {
    final shared = expenseOf(
      'ge',
      userId: 'u1',
      groupId: 'g1',
    ).copyWith(amount: Money(3000, 'EUR'));

    testWidgets('someone who shares it left: amount and group are locked', (
      tester,
    ) async {
      final (backend, _) = await _pump(
        tester,
        expense: shared,
        rows: [shared],
        setUp: (b) {
          b.groups.membersByGroup['g1'] = [memberOf('u1')];
          b.expenses.participants['ge'] = ['u1', 'u-left'];
        },
      );

      expect(find.byKey(const Key('expense-locked')), findsOneWidget);
      expect(
        find.textContaining('someone in it has left the group'),
        findsOneWidget,
      );
      final amount = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('expense-amount')),
          matching: find.byType(TextField),
        ),
      );
      expect(amount.enabled, isFalse);

      // Moving to personal is refused with the same reason.
      await _tapScope(tester, 'Personal');
      expect(backend.expenses.moves, isEmpty);

      await tester.enterText(find.byKey(const Key('expense-title')), 'Dinner');
      await _save(tester);
      final saved = backend.expenses.rows.single;
      expect(saved.title, 'Dinner');
      expect(saved.amount, Money(3000, 'EUR'));
      expect(saved.groupId, 'g1');
    });

    testWidgets('a lock reported by the server restores the amount', (
      tester,
    ) async {
      final (backend, _) = await _pump(
        tester,
        expense: shared,
        rows: [shared],
        setUp: (b) => b.groups.membersByGroup['g1'] = [memberOf('u1')],
      );
      expect(find.byKey(const Key('expense-locked')), findsNothing);

      backend.expenses.failWrites = const AppFailure.business(
        'expense_locked_member_left',
      );
      await tester.enterText(find.byKey(const Key('expense-amount')), '45');
      await _save(tester);

      expect(find.byType(AddEditExpenseSheet), findsOneWidget);
      expect(
        find.text(
          "This expense can't be changed because someone in it has left the "
          'group.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('expense-locked')), findsOneWidget);
      expect(find.text('30.00'), findsOneWidget);

      backend.expenses.failWrites = null;
      await tester.enterText(find.byKey(const Key('expense-title')), 'Dinner');
      await _save(tester);
      expect(backend.expenses.rows.single.amount, Money(3000, 'EUR'));
      expect(backend.expenses.rows.single.title, 'Dinner');
    });
  });

  testWidgets('asks before discarding unsaved changes', (tester) async {
    // Tall enough to leave the barrier visible above the sheet.
    await _pump(tester, height: 1400);

    await tester.enterText(find.byKey(const Key('expense-title')), 'Draft');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(AddEditExpenseSheet), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);

    // Back asks as well.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();

    // And so does tapping outside the sheet.
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
    await _tapScope(tester, 'Group');
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
    backend.expenses.failWrites = const AppFailure.permissionDenied();

    await tester.enterText(find.byKey(const Key('expense-amount')), '10');
    await tester.enterText(find.byKey(const Key('expense-title')), 'Coffee');
    await _save(tester);

    expect(find.byKey(const Key('expense-form-error')), findsOneWidget);
    expect(
      find.text(friendlyMessage(const AppFailure.permissionDenied())),
      findsOneWidget,
    );
    expect(find.byType(AddEditExpenseSheet), findsOneWidget);
    expect(backend.expenses.rows, isEmpty);
    // Shown once, in the sheet, not under the modal barrier.
    expect(container.read(failureReporterProvider), isNull);
  });

  testWidgets('a save lost in transit asks to check before retrying', (
    tester,
  ) async {
    final (backend, _) = await _pump(tester);
    backend.expenses.failWrites = const AppFailure.network();

    await tester.enterText(find.byKey(const Key('expense-amount')), '10');
    await tester.enterText(find.byKey(const Key('expense-title')), 'Coffee');
    await _save(tester);

    expect(
      find.text(friendlyMessageForKey('expense_unconfirmed')),
      findsOneWidget,
    );
    expect(find.byType(AddEditExpenseSheet), findsOneWidget);
  });

  for (final mode in themeModes) {
    testWidgets('the sheet meets contrast and tap-target guidelines ($mode)', (
      tester,
    ) async {
      await _pump(tester, mode: mode);
      expect(find.text('Add expense'), findsOneWidget);
      await expectAccessibleScreen(tester);
    });

    testWidgets('a locked expense meets the guidelines ($mode)', (
      tester,
    ) async {
      final shared = expenseOf(
        'ge',
        userId: 'u1',
        groupId: 'g1',
      ).copyWith(amount: Money(3000, 'EUR'));
      await _pump(
        tester,
        mode: mode,
        expense: shared,
        rows: [shared],
        setUp: (b) {
          b.groups.membersByGroup['g1'] = [memberOf('u1')];
          b.expenses.participants['ge'] = ['u1', 'u-left'];
        },
      );
      expect(find.byKey(const Key('expense-locked')), findsOneWidget);
      await expectAccessibleScreen(tester);
    });

    testWidgets('the sheet fits 320dp at 200% text ($mode)', (tester) async {
      await _pump(tester, mode: mode, width: 320, textScale: 2);
      await tester.enterText(find.byKey(const Key('expense-title')), 'Taxi');
      await _save(tester);
      expectNoOverflow(tester);
      expect(find.byType(AddEditExpenseSheet), findsOneWidget);
    });
  }

  testWidgets('a comma is read as the decimal point', (tester) async {
    final (backend, _) = await _pump(tester);

    await tester.enterText(find.byKey(const Key('expense-amount')), '12,5');
    await tester.enterText(find.byKey(const Key('expense-title')), 'Tea');
    await _save(tester);

    expect(backend.expenses.rows.single.amount, Money(1250, 'EUR'));
  });

  testWidgets('letters and minus signs are never typed into the amount', (
    tester,
  ) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('expense-amount')), '-1a2');
    await tester.pump();
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('an empty title is refused inline', (tester) async {
    final (backend, _) = await _pump(tester);
    await tester.enterText(find.byKey(const Key('expense-amount')), '5');
    await _save(tester);
    expect(find.text('Enter a title.'), findsOneWidget);
    expect(backend.expenses.rows, isEmpty);
  });

  testWidgets('Undo after a move with edits restores every field', (
    tester,
  ) async {
    final original = expenseOf('e1', userId: 'u1', title: 'Groceries').copyWith(
      amount: Money(4000, 'INR'),
      note: 'Weekly',
      category: 'Shopping',
    );
    final (backend, _) = await _pump(
      tester,
      expense: original,
      rows: [original],
      rootMessenger: true,
    );

    await _tapScope(tester, 'Group');
    expect(find.byKey(const Key('expense-currency-locked')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('expense-amount')), '55');
    await tester.enterText(find.byKey(const Key('expense-title')), 'Shared');
    await _save(tester);

    final moved = backend.expenses.rows.single;
    expect(moved.groupId, 'g1');
    expect(moved.title, 'Shared');
    expect(moved.amount, Money(5500, 'EUR'));
    expect(find.textContaining('Moved "Shared"'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    final restored = backend.expenses.rows.single;
    expect(restored.isPersonal, isTrue);
    expect(restored.title, 'Groceries');
    expect(restored.amount, Money(4000, 'INR'));
    expect(restored.note, 'Weekly');
    expect(restored.category, 'Shopping');
    expect(find.text('"Groceries" is back as it was'), findsOneWidget);
    rootScaffoldMessengerKey.currentState?.clearSnackBars();
  });
}
