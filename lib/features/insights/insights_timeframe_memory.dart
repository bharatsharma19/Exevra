import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../core/storage/preferences.dart';
import '../../models/insights.dart';

/// Remembers the insights time range per user on this device, so the
/// screen opens on the range the user last picked. The key is a per-user
/// preference, removed when that user signs out.
abstract final class InsightsTimeframeMemory {
  /// Preference name (namespaced per user by [UserPrefs.key]).
  static const String name = 'insights_timeframe';

  /// The saved range of [userId], or null when none was saved or it could
  /// not be read.
  static InsightTimeframe? read(SharedPreferences prefs, String userId) {
    try {
      final saved = prefs.getString(UserPrefs.key(userId, name));
      for (final t in InsightTimeframe.values) {
        if (t.name == saved) return t;
      }
    } on Object catch (error) {
      AppLogger.warn('Could not read the insights range', error.runtimeType);
    }
    return null;
  }

  /// Saves [timeframe] for [userId]. A failed save only means the next
  /// visit opens on the default range.
  static Future<void> save(
    SharedPreferences prefs,
    String userId,
    InsightTimeframe timeframe,
  ) async {
    try {
      await prefs.setString(UserPrefs.key(userId, name), timeframe.name);
    } on Object catch (error) {
      AppLogger.warn('Could not save the insights range', error.runtimeType);
    }
  }
}
