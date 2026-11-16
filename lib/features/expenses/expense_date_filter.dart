import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../models/expense.dart';
import '../../providers/auth_provider.dart';

/// Date ranges the expenses screen can filter by.
enum ExpenseDatePreset {
  /// No date filter.
  any,

  /// The last 7 days, today included (nothing dated after today).
  last7Days,

  /// The whole calendar month, later-dated expenses in it included.
  thisMonth,

  /// The whole previous month.
  lastMonth,

  /// The last three calendar months, the whole of this one included.
  last3Months,

  /// The whole calendar year, later-dated expenses in it included.
  thisYear,
}

/// A local-time range: [start] inclusive, [end] exclusive.
typedef LocalDateRange = ({DateTime start, DateTime end});

/// The range of [preset] around the local time [now], or null for
/// [ExpenseDatePreset.any]. Calendar presets cover their whole month or
/// year, so an expense dated later this month (a bill due next week) is
/// not dropped; only "Last 7 days" stops at today.
LocalDateRange? dateRangeOf(ExpenseDatePreset preset, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final nextMonth = DateTime(now.year, now.month + 1);
  return switch (preset) {
    ExpenseDatePreset.any => null,
    ExpenseDatePreset.last7Days => (
      start: DateTime(today.year, today.month, today.day - 6),
      end: tomorrow,
    ),
    ExpenseDatePreset.thisMonth => (
      start: DateTime(now.year, now.month),
      end: nextMonth,
    ),
    ExpenseDatePreset.lastMonth => (
      start: DateTime(now.year, now.month - 1),
      end: DateTime(now.year, now.month),
    ),
    ExpenseDatePreset.last3Months => (
      start: DateTime(now.year, now.month - 2),
      end: nextMonth,
    ),
    ExpenseDatePreset.thisYear => (
      start: DateTime(now.year),
      end: DateTime(now.year + 1),
    ),
  };
}

/// Whether [expense] was spent inside [range] (local time).
bool inDateRange(Expense expense, LocalDateRange? range) {
  if (range == null) return true;
  final local = expense.spentAt.toLocal();
  return !local.isBefore(range.start) && local.isBefore(range.end);
}

/// The label of [preset].
String datePresetLabel(AppLocalizations l10n, ExpenseDatePreset preset) =>
    switch (preset) {
      ExpenseDatePreset.any => l10n.expensesDateAny,
      ExpenseDatePreset.last7Days => l10n.expensesDateLast7Days,
      ExpenseDatePreset.thisMonth => l10n.expensesDateThisMonth,
      ExpenseDatePreset.lastMonth => l10n.expensesDateLastMonth,
      ExpenseDatePreset.last3Months => l10n.expensesDateLast3Months,
      ExpenseDatePreset.thisYear => l10n.expensesDateThisYear,
    };

/// The expenses screen's date filter. It is applied to the loaded pages:
/// the list is ordered newest first, so the screen keeps loading pages
/// until the oldest loaded expense is before the range start, and then it
/// has every expense in the range. Reset when the user changes.
class ExpenseDatePresetNotifier extends Notifier<ExpenseDatePreset> {
  @override
  ExpenseDatePreset build() {
    ref.watch(currentUserIdProvider);
    return ExpenseDatePreset.any;
  }

  /// Chooses [preset].
  void set(ExpenseDatePreset preset) => state = preset;
}

/// See [ExpenseDatePresetNotifier].
final expenseDatePresetProvider =
    NotifierProvider<ExpenseDatePresetNotifier, ExpenseDatePreset>(
      ExpenseDatePresetNotifier.new,
    );
