/// Model representing aggregated analytics returned by get_expense_insights RPC
class FinancialInsight {
  final String timeframe;
  final double totalAmount;
  final int expenseCount;
  final double averageDaily;
  final ExpenseHighlight? highestExpense;
  final List<CategoryExpense> categoryBreakdown;
  final List<TrendPoint> trendData;

  const FinancialInsight({
    required this.timeframe,
    required this.totalAmount,
    required this.expenseCount,
    required this.averageDaily,
    this.highestExpense,
    required this.categoryBreakdown,
    required this.trendData,
  });

  factory FinancialInsight.empty([String timeframe = 'monthly']) {
    return FinancialInsight(
      timeframe: timeframe,
      totalAmount: 0.0,
      expenseCount: 0,
      averageDaily: 0.0,
      highestExpense: null,
      categoryBreakdown: const [],
      trendData: const [],
    );
  }

  factory FinancialInsight.fromJson(Map<String, dynamic> json) {
    final rawTotal = json['total_amount'];
    final double total = rawTotal is num ? rawTotal.toDouble() : 0.0;

    final rawAvg = json['average_daily'];
    final double avg = rawAvg is num ? rawAvg.toDouble() : 0.0;

    ExpenseHighlight? highest;
    if (json['highest_expense'] != null && json['highest_expense'] is Map && (json['highest_expense'] as Map).isNotEmpty) {
      highest = ExpenseHighlight.fromJson(Map<String, dynamic>.from(json['highest_expense'] as Map));
    }

    final List<CategoryExpense> categories = [];
    if (json['category_breakdown'] != null && json['category_breakdown'] is List) {
      for (final item in json['category_breakdown'] as List) {
        if (item is Map) {
          categories.add(CategoryExpense.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final List<TrendPoint> trends = [];
    if (json['trend_data'] != null && json['trend_data'] is List) {
      for (final item in json['trend_data'] as List) {
        if (item is Map) {
          trends.add(TrendPoint.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    return FinancialInsight(
      timeframe: json['timeframe'] as String? ?? 'monthly',
      totalAmount: total,
      expenseCount: json['expense_count'] as int? ?? 0,
      averageDaily: avg,
      highestExpense: highest,
      categoryBreakdown: categories,
      trendData: trends,
    );
  }
}

class CategoryExpense {
  final String category;
  final double total;
  final int count;
  final double percentage;

  const CategoryExpense({
    required this.category,
    required this.total,
    required this.count,
    required this.percentage,
  });

  factory CategoryExpense.fromJson(Map<String, dynamic> json) {
    final rawTotal = json['total'];
    final double total = rawTotal is num ? rawTotal.toDouble() : 0.0;

    final rawPct = json['percentage'];
    final double percentage = rawPct is num ? rawPct.toDouble() : 0.0;

    return CategoryExpense(
      category: json['category'] as String? ?? 'Other',
      total: total,
      count: json['count'] as int? ?? 0,
      percentage: percentage,
    );
  }
}

class TrendPoint {
  final String label;
  final DateTime pointDate;
  final double total;
  final int count;

  const TrendPoint({
    required this.label,
    required this.pointDate,
    required this.total,
    required this.count,
  });

  factory TrendPoint.fromJson(Map<String, dynamic> json) {
    final rawTotal = json['total'];
    final double total = rawTotal is num ? rawTotal.toDouble() : 0.0;

    DateTime date;
    if (json['point_date'] != null) {
      date = DateTime.tryParse(json['point_date'] as String) ?? DateTime.now();
    } else {
      date = DateTime.now();
    }

    return TrendPoint(
      label: json['label'] as String? ?? '',
      pointDate: date,
      total: total,
      count: json['count'] as int? ?? 0,
    );
  }
}

class ExpenseHighlight {
  final String? id;
  final String title;
  final double amount;
  final String category;
  final DateTime date;

  const ExpenseHighlight({
    this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
  });

  factory ExpenseHighlight.fromJson(Map<String, dynamic> json) {
    final rawAmount = json['amount'];
    final double amount = rawAmount is num ? rawAmount.toDouble() : 0.0;

    return ExpenseHighlight(
      id: json['id'] as String?,
      title: json['title'] as String? ?? 'Expense',
      amount: amount,
      category: json['category'] as String? ?? 'Other',
      date: json['date'] != null
          ? DateTime.tryParse(json['date'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
