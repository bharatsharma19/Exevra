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
    this.serverAverageDaily,
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

  /// By total, largest first.
  final List<CategoryTotal> categories;

  /// Days for week/month (zero-filled), months for year; oldest first.
  final List<TrendBucket> buckets;
  final InsightExpense? highest;
  final List<Money> otherCurrencyTotals;

  /// Average per local day as computed by the server, when sent.
  final Money? serverAverageDaily;

  bool get isEmpty => count == 0 && total.isZero;

  /// Average spend per local day of the window (server value when given).
  Money get averageDaily =>
      serverAverageDaily ??
      (buckets.isEmpty
          ? Money.zero(currency)
          : Money(total.amountMinor ~/ buckets.length, currency));

  CategoryTotal? get topCategory =>
      categories.isEmpty ? null : categories.first;

  /// Parses the RPC result. The server sends one block per currency with
  /// the primary currency (group currency, or the profile currency for
  /// personal scope) first; [preferredCurrency] is used only when the
  /// result has no blocks at all.
  factory ExpenseInsights.fromJson(
    Object? data, {
    required InsightScope scope,
    required InsightTimeframe timeframe,
    required String preferredCurrency,
  }) {
    final r = JsonReader.of(data, 'ExpenseInsights');
    final blocks = r.objects('currencies', _CurrencyBlock.fromJson);
    final primaryCode =
        r.optString('primary_currency')?.trim().toUpperCase() ??
        (blocks.isEmpty ? preferredCurrency : blocks.first.currency);

    _CurrencyBlock? primary;
    for (final b in blocks) {
      if (b.currency == primaryCode) {
        primary = b;
        break;
      }
    }
    if (primary == null) {
      return ExpenseInsights(
        scope: scope,
        timeframe: timeframe,
        currency: primaryCode,
        total: Money.zero(primaryCode),
        count: 0,
        categories: const [],
        buckets: const [],
        otherCurrencyTotals: [
          for (final b in blocks)
            if (!b.total.isZero) b.total,
        ],
      );
    }

    final total = primary.total;
    final categories = [...primary.categories]
      ..sort((a, b) => b.total.amountMinor.compareTo(a.total.amountMinor));
    final buckets = [...primary.buckets]
      ..sort((a, b) => a.date.compareTo(b.date));

    return ExpenseInsights(
      scope: scope,
      timeframe: timeframe,
      currency: primaryCode,
      total: total,
      count: primary.count,
      categories: [
        for (final c in categories)
          c.withShare(
            total.amountMinor == 0
                ? 0
                : c.total.amountMinor / total.amountMinor,
          ),
      ],
      buckets: buckets,
      serverAverageDaily: primary.averageDaily,
      highest: primary.highest,
      otherCurrencyTotals: [
        for (final b in blocks)
          if (b.currency != primaryCode && !b.total.isZero) b.total,
      ],
    );
  }
}

/// One currency's block of the insights result.
class _CurrencyBlock {
  const _CurrencyBlock({
    required this.currency,
    required this.total,
    required this.count,
    required this.categories,
    required this.buckets,
    this.averageDaily,
    this.highest,
  });

  final String currency;
  final Money total;
  final int count;
  final List<CategoryTotal> categories;
  final List<TrendBucket> buckets;
  final Money? averageDaily;
  final InsightExpense? highest;

  static _CurrencyBlock fromJson(Object? data) {
    final r = JsonReader.of(data, 'InsightCurrency');
    final total = r.money('total_minor');
    final code = total.currency;
    // Rows inside a block carry no currency of their own.
    Map<String, dynamic> withCode(Object? item, String model) => {
      ...JsonReader.of(item, model).json,
      'currency': code,
    };
    final average = r.optInteger('average_daily_minor');
    final highest = r.optObject('highest');
    return _CurrencyBlock(
      currency: code,
      total: total,
      count: r.optInteger('expense_count') ?? 0,
      categories: r.objects(
        'categories',
        (item) => CategoryTotal.fromJson(withCode(item, 'CategoryTotal')),
      ),
      buckets: r.objects(
        'series',
        (item) => TrendBucket.fromJson(withCode(item, 'TrendBucket')),
      ),
      averageDaily: average == null ? null : Money(average, code),
      highest: highest == null
          ? null
          : InsightExpense.fromJson(withCode(highest, 'InsightExpense')),
    );
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
    // Day buckets are `yyyy-MM-dd`, month buckets `yyyy-MM`.
    final raw = r.string('bucket');
    final month = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(raw);
    return TrendBucket(
      date: month != null
          ? DateTime.utc(int.parse(month[1]!), int.parse(month[2]!))
          : r.date('bucket'),
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
    this.groupId,
  });

  final String? id;

  /// Null for a personal expense.
  final String? groupId;
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
      groupId: r.optString('group_id'),
    );
  }
}
