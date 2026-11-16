import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/accessibility/reduce_motion.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/insights.dart';
import '../../../models/money.dart';
import '../insights_chart_data.dart';

/// Spending per day (week, month) or per month (year) as bars, with round
/// gridlines, every day or month of the window present (zero when nothing
/// was spent) and a spoken summary for screen readers.
class SpendingTrendChart extends StatelessWidget {
  const SpendingTrendChart({
    required this.buckets,
    required this.timeframe,
    required this.currency,
    required this.period,
    super.key,
  });

  /// Zero-filled buckets, oldest first (see [zeroFilledBuckets]).
  final List<TrendBucket> buckets;
  final InsightTimeframe timeframe;
  final String currency;

  /// "Last 30 days" and so on.
  final String period;

  bool get _byMonth => timeframe == InsightTimeframe.year;

  /// Short label under a bar: "Mon" (week), "12 Nov" (month), "Nov" (year)
  /// in the device locale.
  String _axisLabel(DateTime date) => switch (timeframe) {
    InsightTimeframe.week => DateFormat.E().format(date),
    InsightTimeframe.month => DateFormat.MMMd().format(date),
    InsightTimeframe.year => DateFormat.MMM().format(date),
  };

  /// Full label for the tooltip and the spoken summary.
  String _fullLabel(DateTime date) => _byMonth
      ? DateFormat.yMMMM().format(date)
      : DateFormat.MMMEd().format(date);

  /// Spoken summary: the period, the highest bucket and how many buckets
  /// had spending.
  String summary(AppLocalizations l10n) {
    var top = buckets.isEmpty ? null : buckets.first;
    for (final b in buckets) {
      if (top == null || b.total.amountMinor > top.total.amountMinor) top = b;
    }
    final active = buckets.where((b) => !b.total.isZero).length;
    return l10n.insightsTrendSummary(
      period,
      top == null ? '' : _fullLabel(top.date),
      top == null
          ? MoneyFormat.format(Money.zero(currency))
          : MoneyFormat.format(top.total),
      active,
      _byMonth
          ? l10n.insightsMonths(buckets.length)
          : l10n.insightsDays(buckets.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final labelStyle = textTheme.labelSmall?.copyWith(
      color: palette.textSecondary,
    );
    final labelSize = scaler.scale(labelStyle?.fontSize ?? 11);

    var maxValue = 0.0;
    for (final b in buckets) {
      final v = chartValue(b.total);
      if (v > maxValue) maxValue = v;
    }
    final axis = niceAxis(maxValue);

    return Semantics(
      container: true,
      label: summary(l10n),
      child: ExcludeSemantics(
        child: AppCard(
          key: const Key('insights-trend'),
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final leftReserved = (labelSize * 4).clamp(36.0, 88.0);
              final plotWidth = constraints.maxWidth - leftReserved;
              // Labels are thinned so they never touch, newest always shown.
              final labelWidth = labelSize * (_byMonth ? 3 : 6) * 0.62 + 8;
              // Labels sit at least one and a half label widths apart: the
              // edge labels are shifted inwards by up to half their width.
              final slot = plotWidth / buckets.length;
              final step = (labelWidth * 1.5 / slot).ceil().clamp(
                1,
                buckets.length,
              );
              final barWidth = (plotWidth / buckets.length * 0.6).clamp(
                2.0,
                22.0,
              );

              return SizedBox(
                height: 200 + labelSize * 2,
                child: BarChart(
                  duration: context.reduceMotion
                      ? Duration.zero
                      : AppDurations.medium,
                  BarChartData(
                    minY: 0,
                    maxY: axis.max,
                    alignment: BarChartAlignment.spaceBetween,
                    borderData: FlBorderData(show: false),
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      horizontalInterval: axis.interval,
                      getDrawingHorizontalLine: (_) =>
                          FlLine(color: palette.outlineVariant, strokeWidth: 1),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: leftReserved,
                          interval: axis.interval,
                          getTitlesWidget: (value, meta) => SideTitleWidget(
                            meta: meta,
                            child: Text(
                              MoneyFormat.compact(
                                Money(
                                  (value *
                                          Money.zero(
                                            currency,
                                          ).info.minorPerMajor)
                                      .round(),
                                  currency,
                                ),
                              ),
                              maxLines: 1,
                              style: labelStyle,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: labelSize * 1.6 + AppSpacing.sm,
                          getTitlesWidget: (value, meta) {
                            final i = value.toInt();
                            final fromEnd = buckets.length - 1 - i;
                            if (i < 0 ||
                                i >= buckets.length ||
                                fromEnd % step != 0) {
                              return const SizedBox.shrink();
                            }
                            return SideTitleWidget(
                              meta: meta,
                              // The first and last labels stay inside the
                              // card instead of hanging past its edge.
                              fitInside: SideTitleFitInsideData.fromTitleMeta(
                                meta,
                              ),
                              child: Text(
                                _axisLabel(buckets[i].date),
                                maxLines: 1,
                                softWrap: false,
                                style: labelStyle,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) => palette.inverseSurface,
                        fitInsideHorizontally: true,
                        fitInsideVertically: true,
                        getTooltipItem: (group, _, _, _) {
                          final b = buckets[group.x];
                          return BarTooltipItem(
                            l10n.insightsBarTooltip(
                              _fullLabel(b.date),
                              MoneyFormat.format(b.total),
                            ),
                            (textTheme.labelMedium ?? const TextStyle())
                                .copyWith(color: palette.onInverseSurface),
                          );
                        },
                      ),
                    ),
                    barGroups: [
                      for (var i = 0; i < buckets.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: chartValue(buckets[i].total),
                              width: barWidth,
                              color: palette.accent,
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(barWidth / 3),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
