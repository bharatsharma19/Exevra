import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../logging/app_logger.dart';

/// The device's IANA time zone (for example `Asia/Kolkata`), stored in
/// `profiles.timezone` and sent to insights so days and months are bucketed
/// in the user's zone.
final deviceTimeZoneProvider = FutureProvider<String>((ref) async {
  return DeviceTimeZone.read();
});

abstract final class DeviceTimeZone {
  /// Reads the zone from the platform; falls back to a zone with the same
  /// current UTC offset when the platform cannot answer.
  static Future<String> read({DateTime? now}) async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      final id = info.identifier.trim();
      if (id.isNotEmpty) return id;
    } on MissingPluginException {
      // Tests and unsupported platforms: use the offset fallback.
    } on PlatformException catch (e) {
      AppLogger.warn('Time zone lookup failed', e.code);
    } on ArgumentError catch (e) {
      AppLogger.warn('Time zone lookup failed', e.message);
    }
    return fallbackForOffset((now ?? DateTime.now()).timeZoneOffset);
  }

  static const Map<int, String> _fractionalZones = {
    330: 'Asia/Kolkata',
    345: 'Asia/Kathmandu',
    270: 'Asia/Kabul',
    210: 'Asia/Tehran',
    390: 'Asia/Yangon',
    570: 'Australia/Darwin',
    525: 'Australia/Eucla',
    630: 'Australia/Lord_Howe',
    765: 'Pacific/Chatham',
    -210: 'America/St_Johns',
    -570: 'Pacific/Marquesas',
  };

  /// An IANA zone with [offset] (no DST rules). Whole hours map to
  /// `Etc/GMT±N` (note the inverted sign of the Etc zones).
  static String fallbackForOffset(Duration offset) {
    final minutes = offset.inMinutes;
    if (minutes == 0) return 'UTC';
    final named = _fractionalZones[minutes];
    if (named != null) return named;
    if (minutes % 60 != 0) return 'UTC';
    final hours = minutes ~/ 60;
    return hours > 0 ? 'Etc/GMT-$hours' : 'Etc/GMT+${-hours}';
  }
}
