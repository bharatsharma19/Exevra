import 'dart:math' as math;

import '../../models/insights.dart';
import '../../models/money.dart';

/// Number of buckets each timeframe's chart shows: 7 days, 30 days or 12
/// months, matching the server window.
int bucketCountOf(InsightTimeframe timeframe) => switch (timeframe) {
  InsightTimeframe.week => 7,
  InsightTimeframe.month => 30,
  InsightTimeframe.year => 12,
};

/// The chart's buckets for [insights]: every day (week, month) or month
/// (year) of the window, oldest first, with zero for the ones without
/// spending.
///
/// The window ends at the newest bucket the server sent, or at [today]
/// (the device's local date) when it sent none. Buckets outside the window
/// are dropped, so the chart always has [bucketCountOf] bars.
List<TrendBucket> zeroFilledBuckets(
  ExpenseInsights insights, {
  required DateTime today,
}) {
  final timeframe = insights.timeframe;
  final byMonth = timeframe == InsightTimeframe.year;
  DateTime keyOf(DateTime d) => byMonth
      ? DateTime.utc(d.year, d.month)
      : DateTime.utc(d.year, d.month, d.day);

  final totals = <DateTime, TrendBucket>{};
  for (final b in insights.buckets) {
    final key = keyOf(b.date);
    final existing = totals[key];
    totals[key] = existing == null
        ? TrendBucket(date: key, total: b.total, count: b.count)
        : TrendBucket(
            date: key,
            total: Money(
              existing.total.amountMinor + b.total.amountMinor,
              existing.total.currency,
            ),
            count: existing.count + b.count,
          );
  }

  final sorted = totals.keys.toList()..sort();
  final end = sorted.isEmpty ? keyOf(today) : sorted.last;
  final count = bucketCountOf(timeframe);
  return [
    for (var i = count - 1; i >= 0; i--)
      () {
        final date = byMonth
            ? DateTime.utc(end.year, end.month - i)
            : DateTime.utc(end.year, end.month, end.day - i);
        return totals[date] ??
            TrendBucket(
              date: date,
              total: Money.zero(insights.currency),
              count: 0,
            );
      }(),
  ];
}

/// A value axis with round gridlines: `0, interval, 2 × interval … max`.
class ChartAxis {
  const ChartAxis({required this.max, required this.interval});

  /// Top of the axis, a whole number of [interval]s.
  final double max;

  /// Distance between gridlines.
  final double interval;
}

/// A "nice" axis for values from 0 to [maxValue] with about [targetLines]
/// gridlines. Steps are 1, 2, 2.5 or 5 times a power of ten and never less
/// than [minInterval] (one whole currency unit by default), so every label
/// is distinct.
ChartAxis niceAxis(
  double maxValue, {
  int targetLines = 4,
  double minInterval = 1,
}) {
  if (!maxValue.isFinite || maxValue <= 0) {
    return ChartAxis(max: minInterval * targetLines, interval: minInterval);
  }
  final raw = maxValue / targetLines;
  final magnitude = math
      .pow(10, (math.log(raw) / math.ln10).floor())
      .toDouble();
  final normalized = raw / magnitude;
  final step = normalized <= 1
      ? 1.0
      : normalized <= 2
      ? 2.0
      : normalized <= 2.5
      ? 2.5
      : normalized <= 5
      ? 5.0
      : 10.0;
  final interval = math.max(step * magnitude, minInterval);
  final lines = math.max(1, (maxValue / interval - 1e-9).ceil());
  return ChartAxis(max: lines * interval, interval: interval);
}

/// Major units of [money] as a double, for chart coordinates only (never
/// for sums or display).
double chartValue(Money money) => money.amountMinor / money.info.minorPerMajor;
