import 'package:clock/clock.dart';
import 'package:expense_manager/core/utils/app_clock.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Now" in every golden: Monday 16 November 2026, noon local time.
///
/// Built from local fields, like every date in golden data ([goldenDay]),
/// so the local calendar day and clock time on screen are the same in
/// every host time zone (no instant sits near a midnight).
final DateTime goldenNow = DateTime(2026, 11, 16, 12);

/// Noon local time on [year]-[month]-[day], as the UTC instant the server
/// would send.
DateTime goldenDay(int year, int month, int day) =>
    DateTime(year, month, day, 12).toUtc();

/// Fixes [AppClock] at [goldenNow] for the tests of this file. Call it
/// first in `main`, before any other `setUpAll`.
void useGoldenClock() {
  setUpAll(() => AppClock.debugOverride = Clock.fixed(goldenNow));
  tearDownAll(() => AppClock.debugOverride = null);
}
