import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/errors/failure_messages.dart';
import 'package:expense_manager/core/utils/money_format.dart';
import 'package:expense_manager/features/insights/screens/insights_screen.dart';
import 'package:expense_manager/models/insights.dart';
import 'package:expense_manager/models/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

Future<TestBackend> _pump(
  WidgetTester tester, {
  bool inGroup = false,
  void Function(TestBackend backend)? setUp,
}) async {
  tester.view.physicalSize = const Size(1200, 3600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final backend = TestBackend(signedInAs: 'u1');
  backend.profiles.profiles['u1'] = profileOf(
    'u1',
    activeGroupId: inGroup ? 'g1' : null,
  );
  backend.groups.groupsByUser['u1'] = [groupOf('g1', adminId: 'u1')];
  setUp?.call(backend);
  final container = await backend.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: InsightsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return backend;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a failed load shows friendly copy and recovers on Retry', (
    tester,
  ) async {
    final backend = await _pump(
      tester,
      setUp: (b) => b.insights.failure = const AppFailure.timeout(),
    );
    expect(
      find.text(friendlyMessage(const AppFailure.timeout())),
      findsOneWidget,
    );

    backend.insights.failure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('insights-empty')), findsOneWidget);
  });

  testWidgets('no spending shows an empty state, labelled by scope', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byKey(const Key('insights-empty')), findsOneWidget);
    expect(find.textContaining('your share of group expenses'), findsOne);
  });

  testWidgets('group scope says so and lists other currencies', (tester) async {
    await _pump(
      tester,
      inGroup: true,
      setUp: (b) => b.insights.byGroup['g1'] = ExpenseInsights(
        scope: InsightScope.group,
        timeframe: InsightTimeframe.month,
        currency: 'INR',
        total: Money(120000, 'INR'),
        count: 3,
        categories: const [],
        buckets: const [],
        otherCurrencyTotals: [Money(2500, 'USD')],
      ),
    );
    expect(find.text('Everything spent in Group g1'), findsOneWidget);
    expect(find.text(MoneyFormat.format(Money(120000, 'INR'))), findsOne);
    expect(
      find.text('Also spent: ${MoneyFormat.format(Money(2500, 'USD'))}'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('insights-empty')), findsNothing);
  });
}
