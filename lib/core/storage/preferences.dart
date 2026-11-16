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
/// * Per-user keys are namespaced `u.<uid>.<name>` and are removed when
///   that user signs out or deletes the account. Only the App Lock flag
///   survives a sign-out (it holds no personal data), so signing in again
///   cannot skip the lock.
abstract final class UserPrefs {
  static const String _prefix = 'u.';

  /// Per-user key for [name].
  static String key(String userId, String name) => '$_prefix$userId.$name';

  static const String haptics = 'haptics';

  /// App Lock on/off for this user.
  static const String appLock = 'app_lock';

  /// Old global keys that held one user's data on the device.
  static const List<String> legacyUserKeys = [
    AppConstants.keyCurrency,
    AppConstants.keyHapticsEnabled,
    AppConstants.keyAiConsent,
    AppConstants.keyCachedProfile,
    AppConstants.keySecureToken,
  ];

  /// Removes every key of [userId] and the legacy global user keys. With
  /// [keepAppLock] the App Lock flag stays, so the next sign-in of the
  /// same account on this device starts locked.
  static Future<void> clearUser(
    SharedPreferences prefs,
    String userId, {
    required bool keepAppLock,
  }) async {
    final ownPrefix = '$_prefix$userId.';
    final lockKey = key(userId, appLock);
    final keys = [
      ...prefs.getKeys().where(
        (k) => k.startsWith(ownPrefix) && !(keepAppLock && k == lockKey),
      ),
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
