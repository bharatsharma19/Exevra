import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../logging/app_logger.dart';

/// Device preferences. Overridden in `main()` with the loaded instance
/// (and in tests with a mock-backed one).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw StateError('sharedPreferencesProvider is not initialised'),
);

/// Keys and clean-up for preferences.
///
/// * Device-wide keys (the theme) survive sign-out.
/// * Per-user keys are namespaced `u.<uid>.<name>` and are all removed
///   when that user signs out or deletes the account.
abstract final class UserPrefs {
  static const String _prefix = 'u.';

  /// Per-user key for [name].
  static String key(String userId, String name) => '$_prefix$userId.$name';

  static const String haptics = 'haptics';

  /// Old global keys that held one user's data on the device.
  static const List<String> legacyUserKeys = [
    AppConstants.keyCurrency,
    AppConstants.keyHapticsEnabled,
    AppConstants.keyAiConsent,
    AppConstants.keyCachedProfile,
    AppConstants.keySecureToken,
  ];

  /// Removes every key of [userId] and the legacy global user keys.
  static Future<void> clearUser(SharedPreferences prefs, String userId) async {
    final ownPrefix = '$_prefix$userId.';
    final keys = [
      ...prefs.getKeys().where((k) => k.startsWith(ownPrefix)),
      ...legacyUserKeys.where(prefs.containsKey),
    ];
    for (final key in keys) {
      try {
        await prefs.remove(key);
      } on Object catch (e) {
        AppLogger.warn('Could not clear a preference', e.runtimeType);
      }
    }
  }
}
