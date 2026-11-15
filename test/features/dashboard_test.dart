import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/errors/failure_messages.dart';
import 'package:expense_manager/core/utils/money_format.dart';
import 'package:expense_manager/features/dashboard/screens/dashboard_screen.dart';
import 'package:expense_manager/features/dashboard/screens/main_navigation_shell.dart';
import 'package:expense_manager/features/expenses/screens/add_edit_expense_sheet.dart';
import 'package:expense_manager/features/onboarding/first_expense_nudge.dart';
import 'package:expense_manager/main.dart';
import 'package:expense_manager/models/insights.dart';
import 'package:expense_manager/models/money.dart';
import 'package:expense_manager/providers/failure_reporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

ExpenseInsights _insights(int totalMinor, {InsightScope? scope}) =>
    ExpenseInsights(
      scope: scope ?? InsightScope.group,
      timeframe: InsightTimeframe.month,
      currency: 'INR',
      total: Money(totalMinor, 'INR'),
      count: 2,
      categories: const [],
      buckets: const [],
    );

Future<(TestBackend, ProviderContainer)> _pump(
  WidgetTester tester, {
  bool inGroup = true,
  void Function(TestBackend backend)? setUp,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final backend = TestBackend(signedInAs: 'u1');
  backend.profiles.profiles['u1'] = profileOf(
    'u1',
    activeGroupId: inGroup ? 'g1' : null,
  );
  backend.groups.groupsByUser['u1'] = [groupOf('g1', adminId: 'u1')];
  backend.expenses.rows.addAll([
    expenseOf('p1', userId: 'u1', title: 'Solo lunch'),
    expenseOf('g1e', userId: 'u2', groupId: 'g1', title: 'Team dinner'),
  ]);
  setUp?.call(backend);
  final container = await backend.container();
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DashboardScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return (backend, container);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('in a group the total, list and balance share one scope', (
    tester,
  ) async {
    await _pump(
      tester,
      setUp: (b) {
        b.insights.byGroup['g1'] = _insights(50000);
        b.balances.balancesByGroup['g1'] = [
          balanceOf('u2', 25000),
          balanceOf('u1', -25000),
        ];
      },
    );

    expect(find.text('GROUP TOTAL'), findsOneWidget);
    expect(find.text(MoneyFormat.format(Money(50000, 'INR'))), findsOneWidget);
    // Recent rows are the group's, like the total above them.
    expect(find.text('Recent group expenses'), findsOneWidget);
    expect(find.text('Team dinner'), findsOneWidget);
    expect(find.text('Solo lunch'), findsNothing);
    expect(
      find.text(
        'Your balance: you owe ${MoneyFormat.format(Money(25000, 'INR'))}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('in personal mode it is the user\'s own spending', (
    tester,
  ) async {
    await _pump(
      tester,
      inGroup: false,
      setUp: (b) => b.insights.byGroup[null] = _insights(
        1000,
        scope: InsightScope.personal,
      ),
    );

    expect(find.text('YOUR SPENDING'), findsOneWidget);
    expect(find.textContaining('your share of group expenses'), findsOneWidget);
    expect(find.text('Solo lunch'), findsOneWidget);
    expect(find.text('Team dinner'), findsNothing);
    expect(find.byKey(const Key('dashboard-my-balance')), findsNothing);
  });

  group('first-expense tip', () {
    testWidgets('shows while there are no expenses and opens the add sheet', (
      tester,
    ) async {
      await _pump(
        tester,
        inGroup: false,
        setUp: (b) => b.expenses.rows.clear(),
      );
      final tip = find.byKey(const Key('dashboard-first-expense'));
      expect(tip, findsOneWidget);
      expect(find.byType(FirstExpenseNudge), findsOneWidget);

      await tester.tap(
        find.descendant(of: tip, matching: find.byType(FilledButton)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AddEditExpenseSheet), findsOneWidget);
    });

    testWidgets('is hidden once there is an expense', (tester) async {
      await _pump(tester, inGroup: false);
      expect(find.text('Solo lunch'), findsOneWidget);
      expect(find.byType(FirstExpenseNudge), findsNothing);
    });

    testWidgets('stays hidden after it was dismissed', (tester) async {
      await _pump(
        tester,
        inGroup: false,
        setUp: (b) => b.expenses.rows.clear(),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('dashboard-first-expense')),
          matching: find.byIcon(Icons.close),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dashboard-first-expense')), findsOneWidget);
      // The tip itself renders nothing once dismissed.
      expect(
        find.descendant(
          of: find.byKey(const Key('dashboard-first-expense')),
          matching: find.byType(FilledButton),
        ),
        findsNothing,
      );
    });
  });

  testWidgets('adding is only on the FAB', (tester) async {
    await _pump(tester);
    expect(find.text('Quick Add'), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byTooltip('Add expense'), findsOneWidget);
  });

  testWidgets('a failed summary shows no figure and offers Retry', (
    tester,
  ) async {
    final (backend, _) = await _pump(
      tester,
      setUp: (b) => b.insights.failure = const AppFailure.network(),
    );

    expect(find.text('—'), findsOneWidget);
    expect(find.text(friendlyMessage(const AppFailure.network())), findsOne);

    backend.insights
      ..failure = null
      ..byGroup['g1'] = _insights(700);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text(MoneyFormat.format(Money(700, 'INR'))), findsOneWidget);
  });

  group('offline', () {
    test('network failures read as offline only while offline', () {
      expect(
        offlineAware(const AppFailure.network(), offline: true),
        const AppFailure.offline(),
      );
      expect(
        offlineAware(const AppFailure.timeout(), offline: true),
        const AppFailure.offline(),
      );
      expect(
        offlineAware(const AppFailure.network(), offline: false),
        const AppFailure.network(),
      );
      expect(
        offlineAware(const AppFailure.permissionDenied(), offline: true),
        const AppFailure.permissionDenied(),
      );
    });

    testWidgets('the shell shows a banner and offline copy', (tester) async {
      final backend = TestBackend(signedInAs: 'u1');
      backend.profiles.profiles['u1'] = profileOf('u1');
      backend.connectivity.online = false;
      final container = (await tester.runAsync(backend.container))!;
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ExevraApp(),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('offline-banner')), findsOneWidget);

      container
          .read(failureReporterProvider.notifier)
          .report(const AppFailure.network());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text(friendlyMessage(const AppFailure.offline())),
        findsOneWidget,
      );

      backend.connectivity.set(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('offline-banner')), findsNothing);
    });
  });
}
