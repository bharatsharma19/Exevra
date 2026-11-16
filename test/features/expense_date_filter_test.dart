import 'package:expense_manager/features/expenses/expense_date_filter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  final now = DateTime(2026, 11, 16, 12);
  bool inRange(ExpenseDatePreset preset, DateTime localDay) => inDateRange(
    expenseOf('e', userId: 'u1', spentAt: localDay.toUtc()),
    dateRangeOf(preset, now),
  );

  test('calendar presets keep later-dated expenses of their period', () {
    final nextWeek = DateTime(2026, 11, 23, 9);
    final lastDayOfMonth = DateTime(2026, 11, 30, 23, 59);
    final december = DateTime(2026, 12, 1, 0, 1);
    expect(inRange(ExpenseDatePreset.thisMonth, nextWeek), isTrue);
    expect(inRange(ExpenseDatePreset.thisMonth, lastDayOfMonth), isTrue);
    expect(inRange(ExpenseDatePreset.thisMonth, december), isFalse);
    expect(inRange(ExpenseDatePreset.last3Months, lastDayOfMonth), isTrue);
    expect(
      inRange(ExpenseDatePreset.last3Months, DateTime(2026, 9, 1)),
      isTrue,
    );
    expect(
      inRange(ExpenseDatePreset.last3Months, DateTime(2026, 8, 31)),
      isFalse,
    );
    expect(inRange(ExpenseDatePreset.thisYear, december), isTrue);
    expect(inRange(ExpenseDatePreset.thisYear, DateTime(2027, 1, 1)), isFalse);
  });

  test('last 7 days ends today and last month is the whole month', () {
    expect(
      inRange(ExpenseDatePreset.last7Days, DateTime(2026, 11, 10)),
      isTrue,
    );
    expect(
      inRange(ExpenseDatePreset.last7Days, DateTime(2026, 11, 9)),
      isFalse,
    );
    expect(
      inRange(ExpenseDatePreset.last7Days, DateTime(2026, 11, 16, 23)),
      isTrue,
    );
    expect(
      inRange(ExpenseDatePreset.last7Days, DateTime(2026, 11, 17)),
      isFalse,
    );
    expect(
      inRange(ExpenseDatePreset.lastMonth, DateTime(2026, 10, 31, 23)),
      isTrue,
    );
    expect(
      inRange(ExpenseDatePreset.lastMonth, DateTime(2026, 11, 1)),
      isFalse,
    );
    expect(dateRangeOf(ExpenseDatePreset.any, now), isNull);
  });
}
