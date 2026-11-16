import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

/// The app's source of "now".
///
/// App code calls [AppClock.now] instead of `DateTime.now()`, so a test
/// can fix the time for a whole test file ([debugOverride], used by the
/// goldens) or for one zone (`withClock` from `package:clock`).
abstract final class AppClock {
  static Clock? _override;

  /// The current local time.
  static DateTime now() => (_override ?? clock).now();

  /// Fixes the time for every caller until reset to null.
  @visibleForTesting
  static set debugOverride(Clock? value) => _override = value;
}
