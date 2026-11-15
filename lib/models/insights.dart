import 'json_reader.dart';
import 'money.dart';

/// Insight scope: the caller's own spending, or a whole group.
enum InsightScope { personal, group }

/// Insight window, bucketed in the user's time zone.
enum InsightTimeframe { week, month, year }

/// Spending summary from `get_expense_insights` for one currency.
///
/// Personal scope = the caller's personal expenses plus their share of
/// group expenses. Amounts in other currencies are never added together;
/// they are listed in [otherCurrencyTotals].
class ExpenseInsights {
  const ExpenseInsights({
    required this.scope,
    required this.timeframe,
    required this.currency,
    required this.total,
    required this.count,
    required this.categories,
    required this.buckets,
    this.highest,
    this.otherCurrencyTotals = const [],
  });

  factory ExpenseInsights.empty({
    required InsightScope scope,
    required InsightTimeframe timeframe,
    required String currency,
  }) => ExpenseInsights(
    scope: scope,
    timeframe: timeframe,
    currency: currency,
    total: Money.zero(currency),
    count: 0,
    categories: const [],
    buckets: const [],
  );

  final InsightScope scope;
  final InsightTimeframe timeframe;

  /// The currency [total], [categories] and [buckets] are in.
  final String currency;
  final Money total;
  final int count;
  final List<CategoryTotal> categories;

  /// Days for week/month (zero-filled), months for year.
  final List<TrendBucket> buckets;
  final InsightExpense? highest;
  final List<Money> otherCurrencyTotals;

  bool get isEmpty => count == 0 && total.isZero;

  /// Average per bucket with spending window length (integer minor units).
  Money get averagePerBucket => buckets.isEmpty
      ? Money.zero(currency)
      : Money(total.amountMinor ~/ buckets.length, currency);

  CategoryTotal? get topCategory =>
      categories.isEmpty ? null : categories.first;

  /// Parses the RPC result, keeping [preferredCurrency] as the primary
  /// currency when it has data (else the currency with the largest total).
  factory ExpenseInsights.fromJson(
    Object? data, {
    required InsightScope scope,
    required InsightTimeframe timeframe,
    required String preferredCurrency,
  }) {
    final r = JsonReader.of(data, 'ExpenseInsights');
    final totals = r.objects('totals', _CurrencyTotal.fromJson);
    final present = {for (final t in totals) t.total.currency: t};

    String primary;
    if (present.containsKey(preferredCurrency) || present.isEmpty) {
      primary = present.isEmpty
          ? (r.optString('currency') ?? preferredCurrency)
          : preferredCurrency;
    } else {
      final sorted = [...totals]
        ..sort((a, b) => b.total.amountMinor.compareTo(a.total.amountMinor));
      primary = sorted.first.total.currency;
    }

    final primaryTotal = present[primary];
    final categories =
        r
            .objects('categories', CategoryTotal.fromJson)
            .where((c) => c.total.currency == primary)
            .toList()
          ..sort((a, b) => b.total.amountMinor.compareTo(a.total.amountMinor));
    final total = primaryTotal?.total ?? Money.zero(primary);
    final withShare = [
      for (final c in categories)
        c.withShare(
          total.amountMinor == 0 ? 0 : c.total.amountMinor / total.amountMinor,
        ),
    ];

    final buckets =
        r
            .objects('buckets', TrendBucket.fromJson)
            .where((b) => b.total.currency == primary)
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    final highestJson = r.optObject('highest');
    final highest = highestJson == null
        ? null
        : InsightExpense.fromJson(highestJson);

    return ExpenseInsights(
      scope: scope,
      timeframe: timeframe,
      currency: primary,
      total: total,
      count: primaryTotal?.count ?? 0,
      categories: withShare,
      buckets: buckets,
      highest: highest != null && highest.amount.currency == primary
          ? highest
          : null,
      otherCurrencyTotals: [
        for (final t in totals)
          if (t.total.currency != primary) t.total,
      ],
    );
  }
}

class _CurrencyTotal {
  const _CurrencyTotal(this.total, this.count);

  final Money total;
  final int count;

  static _CurrencyTotal fromJson(Object? data) {
    final r = JsonReader.of(data, 'InsightTotal');
    return _CurrencyTotal(r.money('total_minor'), r.optInteger('count') ?? 0);
  }
}

/// Spending in one category.
class CategoryTotal {
  const CategoryTotal({
    required this.category,
    required this.total,
    required this.count,
    this.share = 0,
  });

  final String category;
  final Money total;
  final int count;

  /// Fraction of the scope total, 0..1.
  final double share;

  CategoryTotal withShare(double value) => CategoryTotal(
    category: category,
    total: total,
    count: count,
    share: value,
  );

  static CategoryTotal fromJson(Object? data) {
    final r = JsonReader.of(data, 'CategoryTotal');
    return CategoryTotal(
      category: r.string('category'),
      total: r.money('total_minor'),
      count: r.optInteger('count') ?? 0,
    );
  }
}

/// Spending in one local day (week/month) or month (year).
class TrendBucket {
  const TrendBucket({
    required this.date,
    required this.total,
    required this.count,
  });

  /// Local calendar date of the bucket start (UTC-flagged, date only).
  final DateTime date;
  final Money total;
  final int count;

  static TrendBucket fromJson(Object? data) {
    final r = JsonReader.of(data, 'TrendBucket');
    return TrendBucket(
      date: r.date('bucket'),
      total: r.money('total_minor'),
      count: r.optInteger('count') ?? 0,
    );
  }
}

/// The largest single expense in the window.
class InsightExpense {
  const InsightExpense({
    required this.title,
    required this.category,
    required this.amount,
    required this.spentAt,
    this.id,
  });

  final String? id;
  final String title;
  final String category;
  final Money amount;
  final DateTime spentAt;

  static InsightExpense fromJson(Object? data) {
    final r = JsonReader.of(data, 'InsightExpense');
    return InsightExpense(
      id: r.optString('id'),
      title: r.string('title'),
      category: r.string('category'),
      amount: r.money('amount_minor'),
      spentAt: r.instant('spent_at'),
    );
  }
}
