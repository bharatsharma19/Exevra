import 'package:expense_manager/core/utils/app_locale.dart';
import 'package:expense_manager/core/utils/date_helpers.dart';
import 'package:expense_manager/features/expenses/screens/add_edit_expense_sheet.dart';
import 'package:expense_manager/features/expenses/screens/expenses_screen.dart';
import 'package:expense_manager/models/expense.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../support/fakes.dart';

/// Opens the sheet for [expense] from a button.
class _Host extends StatelessWidget {
  const _Host(this.expense);

  final Expense expense;

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

Future<void> _pump(WidgetTester tester, Widget home, List<Expense> rows) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final backend = TestBackend(signedInAs: 'u1');
  backend.profiles.profiles['u1'] = profileOf('u1');
  backend.expenses.rows.addAll(rows);
  final container = await backend.container();
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final rows = [
    expenseOf('today', userId: 'u1', title: 'Today row'),
    expenseOf(
      'old',
      userId: 'u1',
      title: 'Old row',
      spentAt: DateTime.utc(2024, 3, 9, 10),
    ),
  ];

  for (final tag in ['en-IN', 'de-DE', 'en']) {
    group('device locale $tag', () {
      setUp(() async {
        final previous = Intl.defaultLocale;
        addTearDown(() => Intl.defaultLocale = previous);
        await AppLocale.useLocale(tag);
      });

      test('every date label formats without locale errors', () {
        final instant = DateTime.utc(2024, 3, 9, 10);
        final now = DateTime.utc(2026, 11, 15, 12);
        expect(DateHelpers.formatDate(instant), isNotEmpty);
        expect(DateHelpers.formatShortDate(instant), isNotEmpty);
        expect(DateHelpers.formatTime(instant), isNotEmpty);
        expect(DateHelpers.sectionHeader(instant, now: now), isNotEmpty);
        expect(
          DateHelpers.sectionHeader(
            now.subtract(const Duration(days: 3)),
            now: now,
          ),
          isNotEmpty,
        );
        expect(DateHelpers.formatRelative(instant, now: now), isNotEmpty);
      });

      testWidgets('the expense list renders its date headers', (tester) async {
        await _pump(tester, const ExpensesScreen(), rows);
        expect(tester.takeException(), isNull);
        expect(find.text('Today row'), findsOneWidget);
        expect(find.text('Old row'), findsOneWidget);
      });

      testWidgets('the expense sheet renders its date and time', (
        tester,
      ) async {
        await _pump(tester, _Host(rows.last), rows);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(AddEditExpenseSheet), findsOneWidget);
      });
    });
  }

  test('an unknown device locale falls back to en_IN', () async {
    final previous = Intl.defaultLocale;
    addTearDown(() => Intl.defaultLocale = previous);
    expect(await AppLocale.useLocale('zz-ZZ'), 'en_IN');
    expect(DateHelpers.formatDate(DateTime.utc(2024, 3, 9)), isNotEmpty);
  });
}
