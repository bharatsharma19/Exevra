import 'dart:async';

import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/errors/failure_messages.dart';
import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:expense_manager/core/utils/money_format.dart';
import 'package:expense_manager/core/widgets/widgets.dart';
import 'package:expense_manager/data/repositories/expense_repository.dart';
import 'package:expense_manager/features/dashboard/screens/dashboard_screen.dart';
import 'package:expense_manager/features/dashboard/screens/main_navigation_shell.dart';
import 'package:expense_manager/features/dashboard/widgets/dashboard_header.dart';
import 'package:expense_manager/features/expenses/screens/add_edit_expense_sheet.dart';
import 'package:expense_manager/features/onboarding/first_expense_nudge.dart';
import 'package:expense_manager/l10n/l10n.dart';
import 'package:expense_manager/main.dart';
import 'package:expense_manager/models/balance.dart';
import 'package:expense_manager/models/insights.dart';
import 'package:expense_manager/models/money.dart';
import 'package:expense_manager/providers/failure_reporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../support/fakes.dart';

final AppLocalizations l10n = lookupAppLocalizations(const Locale('en'));

ExpenseInsights _insights(
  int totalMinor, {
  InsightScope? scope,
  List<Money> others = const [],
  int count = 2,
}) => ExpenseInsights(
  scope: scope ?? InsightScope.group,
  timeframe: InsightTimeframe.month,
  currency: 'INR',
  total: Money(totalMinor, 'INR'),
  count: count,
  categories: [
    CategoryTotal(
      category: 'Food',
      total: Money(totalMinor, 'INR'),
      count: 2,
      share: 1,
    ),
  ],
  buckets: const [],
  highest: InsightExpense(
    title: 'Team dinner',
    category: 'Food',
    amount: Money(totalMinor ~/ 2, 'INR'),
    spentAt: DateTime.utc(2026, 11, 1),
  ),
  otherCurrencyTotals: others,
);

Future<(TestBackend, ProviderContainer)> _pump(
  WidgetTester tester, {
  bool inGroup = true,
  void Function(TestBackend backend)? setUp,
  ThemeData? theme,
  Size size = const Size(400, 1600),
  double textScale = 1,
  bool settle = true,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  if (textScale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

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
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: const DashboardScreen(),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return (backend, container);
}

void _richGroup(TestBackend b) {
  b.insights.byGroup['g1'] = _insights(50000, others: [Money(2500, 'USD')]);
  b.groups.membersByGroup['g1'] = [memberOf('u1'), memberOf('u2')];
  b.balances.balancesByGroup['g1'] = [
    balanceOf('u2', 25000),
    balanceOf('u1', -25000),
  ];
  b.balances.suggestionsByGroup['g1'] = [
    SettleSuggestion(fromUser: 'u1', toUser: 'u2', amount: Money(25000, 'INR')),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (name, theme) in [
    ('light', AppTheme.light()),
    ('dark', AppTheme.dark()),
  ]) {
    group('$name theme', () {
      testWidgets('content meets contrast and tap-target guidelines', (
        tester,
      ) async {
        await _pump(tester, theme: theme, setUp: _richGroup);
        expect(find.text(l10n.dashboardGroupTotal), findsOneWidget);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      });

      testWidgets('status and navigation bar icons match the theme', (
        tester,
      ) async {
        await _pump(tester, theme: theme, setUp: _richGroup);
        final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find
              .ancestor(
                of: find.byType(Scaffold).first,
                matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
              )
              .first,
        );
        final icons = theme.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark;
        expect(region.value.statusBarIconBrightness, icons);
        expect(region.value.systemNavigationBarIconBrightness, icons);
      });

      testWidgets('empty personal view meets the guidelines', (tester) async {
        await _pump(
          tester,
          inGroup: false,
          theme: theme,
          setUp: (b) => b.expenses.rows.clear(),
        );
        expect(find.byType(FirstExpenseNudge), findsOneWidget);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      });

      testWidgets('fits 320dp at 200% text', (tester) async {
        await _pump(
          tester,
          theme: theme,
          size: const Size(320, 4000),
          textScale: 2,
          setUp: _richGroup,
        );
        expect(tester.takeException(), isNull);
        expect(find.text(l10n.dashboardGroupTotal), findsOneWidget);
        expect(find.byKey(const Key('dashboard-settle-up')), findsOneWidget);
      });

      testWidgets('empty and error states fit 320dp at 200% text', (
        tester,
      ) async {
        await _pump(
          tester,
          theme: theme,
          inGroup: false,
          size: const Size(320, 4000),
          textScale: 2,
          setUp: (b) {
            b.insights.failure = const AppFailure.network();
            b.expenses.rows.clear();
          },
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('dashboard-empty')), findsOneWidget);
      });
    });
  }

  testWidgets('in a group the total, list and balance share one scope', (
    tester,
  ) async {
    await _pump(tester, setUp: _richGroup);

    expect(find.text(l10n.dashboardGroupTotal), findsOneWidget);
    expect(find.text(l10n.dashboardGroupScopeNote('Group g1')), findsOneWidget);
    expect(find.text(l10n.insightsPeriodMonth), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('dashboard-total')),
        matching: find.text(MoneyFormat.format(Money(50000, 'INR'))),
      ),
      findsOneWidget,
    );
    // Recent rows are the group's, like the total above them.
    expect(find.text(l10n.dashboardRecentGroup('Group g1')), findsOneWidget);
    expect(find.text('Team dinner'), findsWidgets);
    expect(find.text('Solo lunch'), findsNothing);
    expect(
      find.text(
        l10n.dashboardBalanceYouOwe(MoneyFormat.format(Money(25000, 'INR'))),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.dashboardYouOwePerson('User u2')), findsOneWidget);
    expect(find.byKey(const Key('dashboard-other-currencies')), findsOneWidget);
  });

  testWidgets("in personal mode it is the user's own spending", (tester) async {
    await _pump(
      tester,
      inGroup: false,
      setUp: (b) => b.insights.byGroup[null] = _insights(
        1000,
        scope: InsightScope.personal,
      ),
    );

    expect(find.text(l10n.dashboardYourSpending), findsOneWidget);
    expect(find.text(l10n.dashboardPersonalScopeNote), findsOneWidget);
    expect(find.text(l10n.dashboardRecentPersonal), findsOneWidget);
    expect(find.text('Solo lunch'), findsOneWidget);
    expect(find.text('Team dinner'), findsWidgets); // the biggest expense
    expect(find.byKey(const Key('dashboard-my-balance')), findsNothing);
  });

  testWidgets('the expense count uses locale digit grouping', (tester) async {
    await _pump(
      tester,
      setUp: (b) => b.insights.byGroup['g1'] = _insights(50000, count: 1234),
    );
    expect(find.text(NumberFormat.decimalPattern().format(1234)), findsOne);
    expect(find.text('1,234'), findsOneWidget);
  });

  testWidgets('the view switcher changes scope', (tester) async {
    await _pump(tester, setUp: _richGroup);
    await tester.tap(find.byKey(const Key('dashboard-scope-button')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.dashboardSwitcherTitle), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(l10n.dashboardSwitcherSelected)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('scope-personal')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.dashboardSwitcherTitle), findsNothing);
    expect(find.text(l10n.dashboardYourSpending), findsOneWidget);
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
      // The tip already offers the action; the empty list does not repeat it.
      expect(
        find.descendant(
          of: find.byKey(const Key('dashboard-empty')),
          matching: find.byType(FilledButton),
        ),
        findsNothing,
      );

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

    testWidgets('an empty group does not show it to a user with expenses', (
      tester,
    ) async {
      await _pump(
        tester,
        setUp: (b) => b.expenses.rows.removeWhere((e) => e.groupId == 'g1'),
      );
      expect(find.text(l10n.dashboardEmptyGroupTitle), findsOneWidget);
      expect(find.byType(FirstExpenseNudge), findsNothing);
    });

    testWidgets('once dismissed, the empty list offers the action', (
      tester,
    ) async {
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
      // The tip itself renders nothing once dismissed.
      expect(
        find.descendant(
          of: find.byKey(const Key('dashboard-first-expense')),
          matching: find.byType(FilledButton),
        ),
        findsNothing,
      );
      final cta = find.descendant(
        of: find.byKey(const Key('dashboard-empty')),
        matching: find.byType(FilledButton),
      );
      expect(cta, findsOneWidget);
      await tester.tap(cta);
      await tester.pumpAndSettle();
      expect(find.byType(AddEditExpenseSheet), findsOneWidget);
    });
  });

  testWidgets('adding is only on the floating button', (tester) async {
    await _pump(tester);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byTooltip(l10n.dashboardAddExpense), findsOneWidget);
  });

  testWidgets('placeholders show while the summary and list load', (
    tester,
  ) async {
    final hold = Completer<ExpensePage>();
    await _pump(
      tester,
      settle: false,
      setUp: (b) => b.expenses.heldFetches.add(hold),
    );
    await tester.pump();
    expect(find.byType(SkeletonList), findsOneWidget);
    expect(find.byType(SkeletonBox), findsWidgets);
    hold.complete(const ExpensePage([], null));
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonList), findsNothing);
  });

  testWidgets('highlights show placeholders while insights load', (
    tester,
  ) async {
    final hold = Completer<void>();
    await _pump(
      tester,
      settle: false,
      setUp: (b) {
        _richGroup(b);
        b.insights.hold = hold;
      },
    );
    await tester.pump();
    for (final key in ['dashboard-top-category', 'dashboard-biggest']) {
      expect(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(SkeletonBox),
        ),
        findsWidgets,
      );
    }
    expect(find.text(l10n.dashboardNoneYet), findsNothing);

    hold.complete();
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('dashboard-top-category')),
        matching: find.byType(SkeletonBox),
      ),
      findsNothing,
    );
    expect(find.text('Food'), findsWidgets);
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
    // The highlights say they could not load, not that there is nothing.
    expect(find.text(l10n.dashboardHighlightFailed), findsNWidgets(2));
    expect(find.text(l10n.dashboardNoneYet), findsNothing);

    backend.insights
      ..failure = null
      ..byGroup['g1'] = _insights(700);
    await tester.tap(find.text(l10n.retry));
    await tester.pumpAndSettle();
    expect(find.text(MoneyFormat.format(Money(700, 'INR'))), findsWidgets);
  });

  testWidgets('a failed list shows an error state with Retry', (tester) async {
    final (backend, _) = await _pump(
      tester,
      setUp: (b) => b.expenses.failReads = const AppFailure.timeout(),
    );
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text(friendlyMessage(const AppFailure.timeout())), findsOne);

    backend.expenses.failReads = null;
    await tester.tap(find.text(l10n.retry));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsNothing);
    expect(find.text('Team dinner'), findsWidgets);
  });

  test('the greeting follows the time of day', () {
    expect(
      DashboardHeader.greeting(l10n, DateTime(2026, 1, 1, 8)),
      l10n.dashboardGreetingMorning,
    );
    expect(
      DashboardHeader.greeting(l10n, DateTime(2026, 1, 1, 13)),
      l10n.dashboardGreetingAfternoon,
    );
    expect(
      DashboardHeader.greeting(l10n, DateTime(2026, 1, 1, 20)),
      l10n.dashboardGreetingEvening,
    );
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
      expect(find.text(l10n.shellOfflineMessage), findsOneWidget);
      expect(find.text(l10n.shellNavHome), findsOneWidget);
      expect(find.text(l10n.shellNavAssistant), findsOneWidget);

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
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(l10n.shellOfflineMessage), findsNothing);
    });
  });
}
