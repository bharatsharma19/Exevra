import 'package:flutter/services.dart';

import '../logging/app_logger.dart';

/// Hides the app from screenshots and the recent-apps preview while App
/// Lock is on (FLAG_SECURE on Android). The native side lives in
/// MainActivity; platforms without it ignore the call.
abstract final class SecureWindow {
  static const MethodChannel channel = MethodChannel('exevra/secure_window');

  static bool? _last;

  /// Turns secure mode on or off. Repeated calls with the same value are
  /// skipped. Never throws.
  static Future<void> setSecure(bool enabled) async {
    if (_last == enabled) return;
    try {
      await channel.invokeMethod<void>('setSecure', {'enabled': enabled});
      _last = enabled;
    } on MissingPluginException {
      // Not implemented on this platform (tests, iOS): nothing to do.
      _last = enabled;
    } on PlatformException catch (e) {
      AppLogger.warn('Secure window could not be changed', e.code);
    }
  }

  /// Forgets the last value (tests).
  static void resetForTest() => _last = null;
}
