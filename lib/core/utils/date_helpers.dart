import 'package:intl/intl.dart';

/// Date and time helpers.
///
/// Rules:
/// * Instants go to the server as UTC ISO-8601 with a `Z` ([toUtcIso]).
/// * Instants from the server are parsed with [parseInstant] (always UTC).
/// * Everything shown to the user is in local wall-clock time.
///
/// Display helpers take an optional [utcOffset] so tests can pin a time
/// zone (for example +05:30 or -08:00) without changing the process zone.
/// When it is null the device's zone is used via [DateTime.toLocal].
abstract final class DateHelpers {
  /// UTC ISO-8601 with a trailing `Z`, for `timestamptz` columns.
  static String toUtcIso(DateTime instant) => instant.toUtc().toIso8601String();

  /// Parses a server timestamp (ISO-8601, any offset) into a UTC instant.
  /// Returns null when [value] is not a valid timestamp.
  static DateTime? parseInstant(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  /// Wall-clock view of [instant]: a DateTime whose year..minute fields are
  /// the local ones. With [utcOffset] it is computed from UTC (the result
  /// is flagged UTC but must only be used for its fields).
  static DateTime wallClock(DateTime instant, {Duration? utcOffset}) {
    if (utcOffset == null) return instant.toLocal();
    return instant.toUtc().add(utcOffset);
  }

  /// The local calendar day of [instant] (time fields zeroed).
  static DateTime localDay(DateTime instant, {Duration? utcOffset}) {
    final wall = wallClock(instant, utcOffset: utcOffset);
    return DateTime.utc(wall.year, wall.month, wall.day);
  }

  /// Whole calendar days from the day of [from] to the day of [to], both
  /// in local time (positive when [to] is later).
  static int calendarDaysBetween(
    DateTime from,
    DateTime to, {
    Duration? utcOffset,
  }) {
    final a = localDay(from, utcOffset: utcOffset);
    final b = localDay(to, utcOffset: utcOffset);
    return (b.difference(a).inHours / 24).round();
  }

  static String formatDate(DateTime instant, {Duration? utcOffset}) =>
      DateFormat.yMMMd().format(wallClock(instant, utcOffset: utcOffset));

  static String formatShortDate(DateTime instant, {Duration? utcOffset}) =>
      DateFormat.MMMd().format(wallClock(instant, utcOffset: utcOffset));

  static String formatTime(DateTime instant, {Duration? utcOffset}) =>
      DateFormat.jm().format(wallClock(instant, utcOffset: utcOffset));

  static String formatMonthYear(DateTime instant, {Duration? utcOffset}) =>
      DateFormat.yMMMM().format(wallClock(instant, utcOffset: utcOffset));

  /// `yyyy-MM-dd` of the local day of [instant].
  static String formatLocalIsoDay(DateTime instant, {Duration? utcOffset}) =>
      DateFormat('yyyy-MM-dd').format(wallClock(instant, utcOffset: utcOffset));

  /// Relative label such as `Just now`, `5 mins ago`, `Yesterday`,
  /// `Tomorrow` or a date. Future instants are never `Just now`.
  static String formatRelative(
    DateTime instant, {
    DateTime? now,
    Duration? utcOffset,
  }) {
    final current = now ?? DateTime.now();
    final diff = current.difference(instant);
    final days = calendarDaysBetween(instant, current, utcOffset: utcOffset);

    if (diff.isNegative) {
      // In the future.
      if (days == 0) return 'Later today';
      if (days == -1) return 'Tomorrow';
      return formatDate(instant, utcOffset: utcOffset);
    }
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) {
      final mins = diff.inMinutes;
      return '$mins ${mins == 1 ? 'min' : 'mins'} ago';
    }
    if (days == 0) {
      final hours = diff.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    }
    if (days == 1) return 'Yesterday';
    if (days < 7) {
      return DateFormat.EEEE().format(wallClock(instant, utcOffset: utcOffset));
    }
    return formatDate(instant, utcOffset: utcOffset);
  }

  /// Section header for a list grouped by local day: `Today`,
  /// `Yesterday`, `Tomorrow`, a weekday within the last week, else a date.
  static String sectionHeader(
    DateTime instant, {
    DateTime? now,
    Duration? utcOffset,
  }) {
    final current = now ?? DateTime.now();
    final days = calendarDaysBetween(instant, current, utcOffset: utcOffset);
    if (days == 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days == -1) return 'Tomorrow';
    final wall = wallClock(instant, utcOffset: utcOffset);
    if (days > 1 && days < 7) return DateFormat.EEEE().format(wall);
    final currentWall = wallClock(current, utcOffset: utcOffset);
    return wall.year == currentWall.year
        ? DateFormat.MMMMd().format(wall)
        : DateFormat.yMMMMd().format(wall);
  }

  /// Combines a local calendar [date] and [hour]:[minute] into a local
  /// instant (as picked in date and time pickers).
  static DateTime combineLocal(DateTime date, int hour, int minute) =>
      DateTime(date.year, date.month, date.day, hour, minute);
}
