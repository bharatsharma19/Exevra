import 'package:expense_manager/data/repositories/expense_repository.dart';
import 'package:expense_manager/features/insights/screens/insights_screen.dart';
import 'package:expense_manager/models/insights.dart';
import 'package:expense_manager/models/money.dart';
import 'package:expense_manager/providers/data_revision.dart';
import 'package:expense_manager/providers/expense_provider.dart';
import 'package:expense_manager/providers/insights_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

ExpenseInsights _figures(int totalMinor, InsightTimeframe timeframe) =>
    ExpenseInsights(
      scope: InsightScope.personal,
      timeframe: timeframe,
      currency: 'INR',
      total: Money(totalMinor, 'INR'),
      count: 1,
      categories: const [],
      buckets: const [],
      otherCurrencyTotals: const [],
    );

TestBackend _backend() {
  final backend = TestBackend(signedInAs: 'u1');
  backend.profiles.profiles['u1'] = profileOf('u1');
  backend.groups.groupsByUser['u1'] = [groupOf('g1', adminId: 'u1')];
  backend.expenses.rows.add(expenseOf('e1', userId: 'u1'));
  return backend;
}

/// The personal insights key for [timeframe], once groups have loaded.
Future<InsightsKey> _keyFor(
  ProviderContainer container,
  InsightTimeframe timeframe,
) async {
  container.listen(activeInsightsKeyProvider(timeframe), (_, _) {});
  for (var i = 0; i < 20; i++) {
    final key = container.read(activeInsightsKeyProvider(timeframe));
    if (key != null) return key;
    await settle();
  }
  fail('groups never finished loading');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AI-20 / CQ-13: an expense edit', () {
    test('keeps the chosen timeframe and refreshes the figures', () async {
      final backend = _backend();
      final container = await backend.container();
      addTearDown(container.dispose);

      container.listen(insightsTimeframeProvider, (_, _) {});
      container
          .read(insightsTimeframeProvider.notifier)
          .set(InsightTimeframe.week);
      final key = await _keyFor(container, InsightTimeframe.week);
      backend.insights.byGroup[null] = _figures(1000, InsightTimeframe.week);
      container.listen(insightsProvider(key), (_, _) {});
      final before = await container.read(insightsProvider(key).future);
      expect(before.total, Money(1000, 'INR'));
      expect(backend.insights.calls, 1);

      // Edit the expense through its list, as the edit sheet does.
      const personal = ExpenseListKey(
        'u1',
        ExpenseQuery(scope: ExpenseScope.personal()),
      );
      container.listen(expenseListProvider(personal), (_, _) {});
      await container.read(expenseListProvider(personal).future);
      backend.insights.byGroup[null] = _figures(4200, InsightTimeframe.week);
      final edited = backend.expenses.rows.single.copyWith(
        amount: Money(4200, 'INR'),
      );
      expect(
        await container
            .read(expenseListProvider(personal).notifier)
            .edit(edited),
        isNull,
      );
      await settle();

      expect(container.read(insightsTimeframeProvider), InsightTimeframe.week);
      expect(
        container.read(activeInsightsKeyProvider(InsightTimeframe.week)),
        key,
      );
      final after = await container.read(insightsProvider(key).future);
      expect(after.total, Money(4200, 'INR'));
      expect(backend.insights.calls, 2);
      expect(backend.insights.timeframes, [
        InsightTimeframe.week,
        InsightTimeframe.week,
      ]);
    });
  });

  group('NEW-04: insights stay idle while nothing shows them', () {
    test('an expense change fetches nothing without a listener', () async {
      final backend = _backend();
      final container = await backend.container();
      addTearDown(container.dispose);
      final key = await _keyFor(container, InsightTimeframe.month);

      container.read(dataRevisionProvider.notifier).bump(DataKind.expenses);
      await settle();
      expect(backend.insights.calls, 0);

      // Shown once, then closed: the cached load is disposed.
      final sub = container.listen(insightsProvider(key), (_, _) {});
      await container.read(insightsProvider(key).future);
      expect(backend.insights.calls, 1);
      sub.close();
      await settle();
      expect(container.read(insightsProvider(key).exists), isFalse);

      container.read(dataRevisionProvider.notifier).bump(DataKind.expenses);
      container.read(dataRevisionProvider.notifier).bump(DataKind.settlements);
      await settle();
      expect(backend.insights.calls, 1);
    });

    test('a paused listener defers the reload until it resumes', () async {
      final backend = _backend();
      final container = await backend.container();
      addTearDown(container.dispose);
      final key = await _keyFor(container, InsightTimeframe.month);

      final sub = container.listen(insightsProvider(key), (_, _) {});
      await container.read(insightsProvider(key).future);
      expect(backend.insights.calls, 1);

      sub.pause();
      for (var i = 0; i < 3; i++) {
        container.read(dataRevisionProvider.notifier).bump(DataKind.expenses);
        await settle();
      }
      expect(backend.insights.calls, 1);

      sub.resume();
      await settle();
      expect(backend.insights.calls, 2);
    });

    testWidgets('a hidden Insights tab does not refetch', (tester) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final backend = _backend();
      final container = await backend.container();
      addTearDown(container.dispose);
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);

      // go_router's indexed shell turns tickers off for tabs not shown,
      // which pauses their providers.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (context, shown, child) =>
                  TickerMode(enabled: shown, child: child!),
              child: const InsightsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(backend.insights.calls, 1);

      visible.value = false;
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        container.read(dataRevisionProvider.notifier).bump(DataKind.expenses);
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(backend.insights.calls, 1);

      visible.value = true;
      await tester.pumpAndSettle();
      expect(backend.insights.calls, 2);
    });
  });
}
