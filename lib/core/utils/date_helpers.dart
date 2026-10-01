import 'package:intl/intl.dart';

/// Date formatting and temporal aggregation utilities
class DateHelpers {
  DateHelpers._();

  static final DateFormat _dayFormat = DateFormat('MMM d, yyyy');
  static final DateFormat _shortDayFormat = DateFormat('MMM d');
  static final DateFormat _timeFormat = DateFormat('h:mm a');
  static final DateFormat _isoFormat = DateFormat('yyyy-MM-dd');
  static final DateFormat _monthYearFormat = DateFormat('MMMM yyyy');

  static String formatDate(DateTime date) => _dayFormat.format(date.toLocal());
  static String formatShortDate(DateTime date) => _shortDayFormat.format(date.toLocal());
  static String formatTime(DateTime date) => _timeFormat.format(date.toLocal());
  static String formatIso(DateTime date) => _isoFormat.format(date);
  static String formatMonthYear(DateTime date) => _monthYearFormat.format(date.toLocal());

  static String formatRelative(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date.toLocal());

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      final mins = difference.inMinutes;
      return '$mins ${mins == 1 ? 'min' : 'mins'} ago';
    } else if (difference.inHours < 24 && date.day == now.day) {
      final hours = difference.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inDays < 2 && date.day == now.subtract(const Duration(days: 1)).day) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return DateFormat('EEEE').format(date);
    } else {
      return _dayFormat.format(date);
    }
  }

  static String getDateSectionHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(date.year, date.month, date.day);

    if (itemDate == today) {
      return 'Today';
    } else if (itemDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else if (today.difference(itemDate).inDays < 7 && today.weekday >= itemDate.weekday) {
      return 'This Week';
    } else if (itemDate.year == now.year && itemDate.month == now.month) {
      return 'This Month';
    } else {
      return _monthYearFormat.format(date);
    }
  }

  static DateTime startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static DateTime endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  }
}
