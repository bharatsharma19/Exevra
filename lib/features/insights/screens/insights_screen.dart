import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_helpers.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/money_format.dart';
import '../../../models/currency_info.dart';
import '../../../models/insights.dart';
import '../../../models/money.dart';
import '../../../providers/groups_provider.dart';
import '../../../providers/insights_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../shared/failure_retry.dart';

class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  int _touchedPieIndex = -1;

  @override
  Widget build(BuildContext context) {
    final timeframe = ref.watch(insightsTimeframeProvider);
    final key = ref.watch(activeInsightsKeyProvider(timeframe));
    final async = key == null
        ? const AsyncLoading<ExpenseInsights>()
        : ref.watch(insightsProvider(key));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final String fallbackCurrency =
        ref.watch(activeGroupProvider)?.currency ??
        ref.watch(preferredCurrencyProvider);
    final insight =
        async.value ??
        ExpenseInsights.empty(
          scope: key?.scope ?? InsightScope.personal,
          timeframe: timeframe,
          currency: fallbackCurrency,
        );
    final currency = insight.currency;
    final trend = insight.buckets;
    final highest = insight.highest;

    Future<void> reload() async {
      if (key == null) return;
      ref.invalidate(insightsProvider(key));
      try {
        await ref.read(insightsProvider(key).future);
      } on Object {
        // Shown by the error state below.
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Financial Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              AppHaptics.light();
              unawaited(reload());
            },
          ),
        ],
      ),
      body: (async.hasError && async.value == null)
          ? Center(
              child: FailureRetry(
                error: async.error!,
                onRetry: () => unawaited(reload()),
              ),
            )
          : async.value == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: reload,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Timeframe Selector Pills
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkCardElevated
                            : AppColors.lightCardElevated,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          _buildTimeframePill(
                            'Weekly',
                            InsightTimeframe.week,
                            timeframe,
                          ),
                          _buildTimeframePill(
                            'Monthly',
                            InsightTimeframe.month,
                            timeframe,
                          ),
                          _buildTimeframePill(
                            'Yearly',
                            InsightTimeframe.year,
                            timeframe,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Primary Metric Banner Card
                    GlassCard(
                      borderRadius: 24,
                      gradient: AppColors.darkCardGradient,
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'TOTAL SPEND (${_timeframeLabel(timeframe)})',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                  color: AppColors.primaryCyan,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryCyan.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${insight.count} Records',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryCyan,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            MoneyFormat.format(insight.total),
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                              color: Colors.white,
                            ),
                          ).animate().fadeIn().slideX(begin: -0.1, end: 0),
                          const SizedBox(height: 14),
                          Divider(color: Colors.white.withValues(alpha: 0.1)),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildSubMetric(
                                'Daily Average',
                                MoneyFormat.format(insight.averageDaily),
                                Icons.calendar_today_rounded,
                              ),
                              _buildSubMetric(
                                'Top Expense',
                                highest != null
                                    ? MoneyFormat.format(highest.amount)
                                    : 'None',
                                Icons.arrow_upward_rounded,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Trend Line/Bar Chart
                    Text(
                      'Spending Velocity & Trends',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassCard(
                      borderRadius: 20,
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                      child: SizedBox(
                        height: 220,
                        child: trend.every((b) => b.total.isZero)
                            ? const Center(
                                child: Text(
                                  'No trend data available for this range',
                                ),
                              )
                            : LineChart(
                                LineChartData(
                                  gridData: FlGridData(
                                    show: true,
                                    drawVerticalLine: false,
                                    getDrawingHorizontalLine: (val) => FlLine(
                                      color: isDark
                                          ? Colors.white10
                                          : Colors.black12,
                                      strokeWidth: 1,
                                    ),
                                  ),
                                  titlesData: FlTitlesData(
                                    rightTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    topTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    leftTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 44,
                                        getTitlesWidget: (val, meta) => Text(
                                          MoneyFormat.compact(
                                            Money(
                                              (val *
                                                      CurrencyInfo.of(
                                                        currency,
                                                      ).minorPerMajor)
                                                  .round(),
                                              currency,
                                            ),
                                          ),
                                          style: TextStyle(
                                            color: isDark
                                                ? AppColors.darkTextTertiary
                                                : AppColors.lightTextTertiary,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 28,
                                        interval: (trend.length / 5).clamp(
                                          1.0,
                                          10.0,
                                        ),
                                        getTitlesWidget: (val, meta) {
                                          final int idx = val.toInt();
                                          if (idx >= 0 && idx < trend.length) {
                                            final rawDate = trend[idx].date;
                                            return Text(
                                              timeframe == InsightTimeframe.year
                                                  ? '${rawDate.month}/${rawDate.year % 100}'
                                                  : '${rawDate.day}/${rawDate.month}',
                                              style: TextStyle(
                                                color: isDark
                                                    ? AppColors.darkTextTertiary
                                                    : AppColors
                                                          .lightTextTertiary,
                                                fontSize: 10,
                                              ),
                                            );
                                          }
                                          return const Text('');
                                        },
                                      ),
                                    ),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  lineBarsData: [
                                    LineChartBarData(
                                      spots: List.generate(trend.length, (i) {
                                        return FlSpot(
                                          i.toDouble(),
                                          trend[i].total.amountMinor /
                                              trend[i].total.info.minorPerMajor,
                                        );
                                      }),
                                      isCurved: true,
                                      curveSmoothness: 0.35,
                                      color: AppColors.primaryCyan,
                                      barWidth: 3,
                                      isStrokeCapRound: true,
                                      dotData: const FlDotData(show: false),
                                      belowBarData: BarAreaData(
                                        show: true,
                                        gradient: LinearGradient(
                                          colors: [
                                            AppColors.primaryCyan.withValues(
                                              alpha: 0.3,
                                            ),
                                            AppColors.primaryCyan.withValues(
                                              alpha: 0.0,
                                            ),
                                          ],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Category Breakdown Donut Chart
                    Text(
                      'Category Breakdown',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassCard(
                      borderRadius: 20,
                      padding: const EdgeInsets.all(20),
                      child: insight.categories.isEmpty
                          ? const Center(
                              child: Text('No categorical expenses to chart'),
                            )
                          : Column(
                              children: [
                                SizedBox(
                                  height: 200,
                                  child: PieChart(
                                    PieChartData(
                                      pieTouchData: PieTouchData(
                                        touchCallback: (event, pieTouchResponse) {
                                          setState(() {
                                            if (!event
                                                    .isInterestedForInteractions ||
                                                pieTouchResponse == null ||
                                                pieTouchResponse
                                                        .touchedSection ==
                                                    null) {
                                              _touchedPieIndex = -1;
                                              return;
                                            }
                                            _touchedPieIndex = pieTouchResponse
                                                .touchedSection!
                                                .touchedSectionIndex;
                                          });
                                        },
                                      ),
                                      borderData: FlBorderData(show: false),
                                      sectionsSpace: 3,
                                      centerSpaceRadius: 50,
                                      sections: List.generate(
                                        insight.categories.length,
                                        (i) {
                                          final item = insight.categories[i];
                                          final isTouched =
                                              i == _touchedPieIndex;
                                          final radius = isTouched
                                              ? 45.0
                                              : 36.0;
                                          final catColor =
                                              AppColors.getCategoryColor(
                                                item.category,
                                              );

                                          return PieChartSectionData(
                                            color: catColor,
                                            value: item.total.amountMinor
                                                .toDouble(),
                                            title:
                                                '${(item.share * 100).toStringAsFixed(0)}%',
                                            radius: radius,
                                            titleStyle: TextStyle(
                                              fontSize: isTouched ? 14 : 11,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                // Category Legends
                                ...insight.categories.map((cat) {
                                  final color = AppColors.getCategoryColor(
                                    cat.category,
                                  );
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: color,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            cat.category,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          MoneyFormat.format(cat.total),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '(${(cat.share * 100).toStringAsFixed(0)}%)',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark
                                                ? AppColors.darkTextTertiary
                                                : AppColors.lightTextTertiary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                    ),

                    const SizedBox(height: 24),

                    // Highest Expense Spotlight
                    if (highest != null) ...[
                      Text(
                        'Peak Transaction Spotlight',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GlassCard(
                        borderRadius: 20,
                        padding: const EdgeInsets.all(18),
                        border: Border.all(
                          color: AppColors.primaryViolet.withValues(alpha: 0.4),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primaryViolet.withValues(
                                  alpha: 0.18,
                                ),
                              ),
                              child: const Icon(
                                Icons.star_rounded,
                                color: AppColors.primaryViolet,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    highest.title,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${highest.category} • ${DateHelpers.formatDate(highest.spentAt)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? AppColors.darkTextTertiary
                                          : AppColors.lightTextTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              MoneyFormat.format(highest.amount),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryViolet,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  static String _timeframeLabel(InsightTimeframe t) => switch (t) {
    InsightTimeframe.week => 'LAST 7 DAYS',
    InsightTimeframe.month => 'LAST 30 DAYS',
    InsightTimeframe.year => 'LAST 12 MONTHS',
  };

  Widget _buildTimeframePill(
    String label,
    InsightTimeframe value,
    InsightTimeframe current,
  ) {
    final isSelected = value == current;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onPrimaryColor = Theme.of(context).colorScheme.onPrimary;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (value == current) return;
          AppHaptics.selection();
          ref.read(insightsTimeframeProvider.notifier).set(value);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
              color: isSelected ? onPrimaryColor : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubMetric(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white70),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.white60),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
