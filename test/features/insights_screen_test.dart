import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/errors/failure_messages.dart';
import 'package:expense_manager/core/storage/preferences.dart';
import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:expense_manager/core/utils/money_format.dart';
import 'package:expense_manager/core/widgets/widgets.dart';
import 'package:expense_manager/features/expenses/screens/add_edit_expense_sheet.dart';
import 'package:expense_manager/features/insights/insights_chart_data.dart';
import 'package:expense_manager/features/insights/insights_timeframe_memory.dart';
import 'package:expense_manager/features/insights/screens/insights_screen.dart';
import 'package:expense_manager/l10n/l10n.dart';
import 'package:expense_manager/models/insights.dart';
import 'package:expense_manager/models/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

final AppLocalizations l10n = lookupAppLocalizations(const Locale('en'));

/// A month of spending: two days with expenses (the rest missing, as a
/// sparse server answer would be), three categories and a USD block.
ExpenseInsights richInsights({
  InsightScope scope = InsightScope.personal,
  InsightTimeframe timeframe = InsightTimeframe.month,
}) => ExpenseInsights(
  scope: scope,
  timeframe: timeframe,
  currency: 'INR',
  total: Money(130000, 'INR'),
  count: 4,
  categories: [
    CategoryTotal(
      category: 'Food',
      total: Money(70000, 'INR'),
      count: 2,
      share: 70000 / 130000,
    ),
    CategoryTotal(
      category: 'Transport',
      total: Money(40000, 'INR'),
      count: 1,
      share: 40000 / 130000,
    ),
    CategoryTotal(
      category: 'Shopping',
      total: Money(20000, 'INR'),
      count: 1,
      share: 20000 / 130000,
    ),
  ],
  buckets: [
    TrendBucket(
      date: DateTime.utc(2026, 11, 3),
      total: Money(50000, 'INR'),
      count: 1,
    ),
    TrendBucket(
      date: DateTime.utc(2026, 11, 15),
      total: Money(80000, 'INR'),
      count: 3,
    ),
  ],
  highest: InsightExpense(
    title: 'Groceries',
    category: 'Food',
    amount: Money(60000, 'INR'),
    // Local noon: the same calendar day in every time zone.
    spentAt: DateTime(2026, 11, 15, 12).toUtc(),
  ),
  otherCurrencyTotals: [Money(2500, 'USD')],
);

Future<(TestBackend, ProviderContainer)> _pump(
  WidgetTester tester, {
  bool inGroup = false,
  void Function(TestBackend backend)? setUp,
  ThemeData? theme,
  Size size = const Size(400, 2400),
  double textScale = 1,
  Map<String, Object> prefs = const {},
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
  setUp?.call(backend);
  final container = await backend.container(prefs: prefs);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: const InsightsScreen(),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return (backend, container);
}

void _rich(TestBackend b) => b.insights.byGroup[null] = richInsights();

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
        await _pump(tester, theme: theme, setUp: _rich);
        expect(find.byKey(const Key('insights-trend')), findsOneWidget);
        expect(find.byKey(const Key('insights-categories')), findsOneWidget);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      });

      testWidgets('the empty state meets the guidelines', (tester) async {
        await _pump(tester, theme: theme);
        expect(find.byKey(const Key('insights-empty')), findsOneWidget);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      });

      testWidgets('the error state meets the guidelines', (tester) async {
        await _pump(
          tester,
          theme: theme,
          setUp: (b) => b.insights.failure = const AppFailure.network(),
        );
        expect(find.byKey(const Key('insights-error')), findsOneWidget);
        expect(find.text(l10n.retry), findsOneWidget);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      });

      testWidgets('content fits 320dp at 200% text', (tester) async {
        await _pump(
          tester,
          theme: theme,
          setUp: _rich,
          size: const Size(320, 5000),
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('insights-trend')), findsOneWidget);
      });

      for (final (state, key, setUp, settle) in [
        ('empty', 'insights-empty', null, true),
        (
          'error',
          'insights-error',
          (TestBackend b) => b.insights.failure = const AppFailure.network(),
          true,
        ),
        ('loading', 'insights-loading', null, false),
      ]) {
        testWidgets('the $state state fits 320dp at 200% text', (tester) async {
          await _pump(
            tester,
            theme: theme,
            size: const Size(320, 3000),
            textScale: 2,
            setUp: setUp,
            settle: settle,
          );
          expect(tester.takeException(), isNull);
          expect(find.byKey(Key(key)), findsOneWidget);
          await tester.pumpAndSettle();
        });
      }
    });
  }

  test('counts use the locale digit grouping', () {
    expect(l10n.insightsExpenseCount(12345), '12,345 expenses');
    expect(l10n.insightsDays(1000), '1,000 days');
  });

  testWidgets('the total is read with its period', (tester) async {
    await _pump(tester, setUp: _rich);
    final total = MoneyFormat.format(richInsights().total);
    final amount = tester.widget<AmountText>(
      find.byKey(const Key('insights-total')),
    );
    expect(
      amount.semanticLabel,
      l10n.insightsTotalLabel(l10n.insightsPeriodMonth, total),
    );
  });

  testWidgets('placeholders show while the first load runs', (tester) async {
    await _pump(tester, setUp: _rich, settle: false);
    expect(find.byKey(const Key('insights-loading')), findsOneWidget);
    expect(find.byType(SkeletonBox), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('insights-loading')), findsNothing);
    expect(find.byKey(const Key('insights-summary')), findsOneWidget);
  });

  testWidgets('a failed load shows friendly copy and recovers on Retry', (
    tester,
  ) async {
    final (backend, _) = await _pump(
      tester,
      setUp: (b) => b.insights.failure = const AppFailure.timeout(),
    );
    expect(find.text(l10n.insightsErrorTitle), findsOneWidget);
    expect(
      find.text(friendlyMessage(const AppFailure.timeout())),
      findsOneWidget,
    );

    backend.insights.failure = null;
    await tester.tap(find.text(l10n.retry));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('insights-empty')), findsOneWidget);
  });

  testWidgets('no spending shows an empty state that adds an expense', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byKey(const Key('insights-empty')), findsOneWidget);
    expect(find.text(l10n.insightsScopePersonal), findsOneWidget);
    await tester.tap(find.text(l10n.insightsAddExpense));
    await tester.pumpAndSettle();
    expect(find.byType(AddEditExpenseSheet), findsOneWidget);
  });

  testWidgets('group scope says so and notes other currencies', (tester) async {
    await _pump(
      tester,
      inGroup: true,
      setUp: (b) =>
          b.insights.byGroup['g1'] = richInsights(scope: InsightScope.group),
    );
    expect(find.text(l10n.insightsScopeGroup('Group g1')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('insights-total')),
        matching: find.text(MoneyFormat.format(Money(130000, 'INR'))),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        l10n.insightsOtherCurrencies(MoneyFormat.format(Money(2500, 'USD'))),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.insightsOtherCurrenciesNote), findsOneWidget);
  });

  testWidgets('charts have spoken summaries and a text legend', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, setUp: _rich);
    expect(
      find.bySemanticsLabel(RegExp('^Bar chart of spending, Last 30 days')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('^Donut chart of spending by category')),
      findsOneWidget,
    );
    // Every category is spelled out as text, never by colour alone.
    for (final c in ['Food', 'Transport', 'Shopping']) {
      expect(
        find.descendant(
          of: find.byKey(const Key('insights-categories')),
          matching: find.text(c),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.bySemanticsLabel(RegExp(r'^Food: .*, 54% of spending, 2 expenses$')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('insights-biggest')), findsOneWidget);
    handle.dispose();
  });

  group('time range', () {
    testWidgets('opens on the range this user picked last', (tester) async {
      await _pump(
        tester,
        setUp: _rich,
        prefs: {UserPrefs.key('u1', InsightsTimeframeMemory.name): 'year'},
      );
      final button = tester.widget<SegmentedButton<InsightTimeframe>>(
        find.byKey(const Key('insights-timeframe')),
      );
      expect(button.selected, {InsightTimeframe.year});
    });

    testWidgets('a new pick is remembered', (tester) async {
      final (_, container) = await _pump(tester, setUp: _rich);
      await tester.tap(find.text(l10n.insightsTimeframeWeek));
      await tester.pumpAndSettle();
      final prefs = container.read(sharedPreferencesProvider);
      expect(
        prefs.getString(UserPrefs.key('u1', InsightsTimeframeMemory.name)),
        'week',
      );
      expect(find.text(l10n.insightsPeriodWeek), findsOneWidget);
    });
  });

  group('chart data', () {
    test('a month is 30 days with the missing ones at zero', () {
      final buckets = zeroFilledBuckets(
        richInsights(),
        today: DateTime(2026, 11, 16),
      );
      expect(buckets, hasLength(30));
      expect(buckets.last.date, DateTime.utc(2026, 11, 15));
      expect(buckets.first.date, DateTime.utc(2026, 10, 17));
      expect(buckets.where((b) => !b.total.isZero), hasLength(2));
      expect(buckets.last.total, Money(80000, 'INR'));
    });

    test('a week is 7 days ending today when nothing was sent', () {
      final buckets = zeroFilledBuckets(
        ExpenseInsights.empty(
          scope: InsightScope.personal,
          timeframe: InsightTimeframe.week,
          currency: 'INR',
        ),
        today: DateTime(2026, 3, 2),
      );
      expect(buckets.map((b) => b.date).toList(), [
        for (var d = 24; d <= 28; d++) DateTime.utc(2026, 2, d),
        DateTime.utc(2026, 3),
        DateTime.utc(2026, 3, 2),
      ]);
      expect(buckets.every((b) => b.total.isZero), isTrue);
    });

    test('a year is 12 month buckets across the year boundary', () {
      final insights = ExpenseInsights(
        scope: InsightScope.personal,
        timeframe: InsightTimeframe.year,
        currency: 'INR',
        total: Money(100, 'INR'),
        count: 1,
        categories: const [],
        buckets: [
          TrendBucket(
            date: DateTime.utc(2026, 2),
            total: Money(100, 'INR'),
            count: 1,
          ),
        ],
      );
      final buckets = zeroFilledBuckets(insights, today: DateTime(2026, 2, 9));
      expect(buckets, hasLength(12));
      expect(buckets.first.date, DateTime.utc(2025, 3));
      expect(buckets.last.date, DateTime.utc(2026, 2));
    });

    test('the axis uses round steps instead of a fixed 50', () {
      void check(double max, double interval, double top) {
        final axis = niceAxis(max);
        expect(axis.interval, interval, reason: 'interval for $max');
        expect(axis.max, top, reason: 'max for $max');
      }

      check(800, 200, 800);
      check(1300, 500, 1500);
      check(9, 2.5, 10);
      check(37000, 10000, 40000);
      check(0.4, 1, 1);
      check(0, 1, 4);
    });
  });
}
