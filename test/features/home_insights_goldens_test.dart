import 'dart:async';

import 'package:alchemist/alchemist.dart';
import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:expense_manager/features/dashboard/widgets/dashboard_cards.dart';
import 'package:expense_manager/features/dashboard/widgets/spending_summary_card.dart';
import 'package:expense_manager/features/insights/insights_chart_data.dart';
import 'package:expense_manager/features/insights/widgets/category_breakdown.dart';
import 'package:expense_manager/features/insights/widgets/insights_summary_card.dart';
import 'package:expense_manager/features/insights/widgets/spending_trend_chart.dart';
import 'package:expense_manager/models/money.dart';
import 'package:flutter/material.dart';

import '../design_system/kit_gallery.dart';
import 'insights_screen_test.dart' show richInsights;
import '../support/golden_clock.dart';

/// The home summary and the insights charts, as the user sees them.
class _HomeAndInsights extends StatelessWidget {
  const _HomeAndInsights();

  @override
  Widget build(BuildContext context) {
    final insights = richInsights();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpendingSummaryCard(
            title: 'Group total',
            period: 'Last 30 days',
            note: 'Everything spent in Goa trip',
            insights: insights,
            loading: false,
            onRetry: () {},
            balance: Money(-25000, 'INR'),
          ),
          const SizedBox(height: 16),
          HighlightsRow(insights: insights),
          const SizedBox(height: 24),
          InsightsSummaryCard(insights: insights, period: 'Last 30 days'),
          const SizedBox(height: 16),
          SpendingTrendChart(
            buckets: zeroFilledBuckets(insights, today: goldenNow),
            timeframe: insights.timeframe,
            currency: insights.currency,
            period: 'Last 30 days',
          ),
          const SizedBox(height: 16),
          CategoryBreakdown(categories: insights.categories),
        ],
      ),
    );
  }
}

/// Regenerate with
/// `flutter test --update-goldens test/features/home_insights_goldens_test.dart`.
void main() {
  useGoldenClock();
  unawaited(
    goldenTest(
      'home summary and insights render in light and dark',
      fileName: 'home_insights',
      pumpBeforeTest: pumpOnce,
      builder: () => GoldenTestGroup(
        columns: 2,
        // Fixed columns: the cards measure themselves with LayoutBuilder,
        // which cannot report intrinsic sizes to the gallery table.
        columnWidthBuilder: (_) => const FixedColumnWidth(400),
        children: [
          for (final (name, theme) in [
            ('light', AppTheme.light()),
            ('dark', AppTheme.dark()),
          ])
            GoldenTestScenario(
              name: name,
              constraints: const BoxConstraints(maxWidth: 400),
              child: ThemedFrame(theme: theme, child: const _HomeAndInsights()),
            ),
        ],
      ),
    ),
  );
}
