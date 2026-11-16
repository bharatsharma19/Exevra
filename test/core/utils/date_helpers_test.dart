import 'package:expense_manager/core/platform/device_time_zone.dart';
import 'package:expense_manager/core/utils/date_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

const ist = Duration(hours: 5, minutes: 30);
const pst = Duration(hours: -8);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('wire format', () {
    test('toUtcIso always ends with Z', () {
      final local = DateTime(2026, 11, 15, 22, 30);
      final iso = DateHelpers.toUtcIso(local);
      expect(iso, endsWith('Z'));
      expect(DateTime.parse(iso).isAtSameMomentAs(local), isTrue);
    });

    test('parseInstant returns UTC for any offset', () {
      final a = DateHelpers.parseInstant('2026-11-15T17:00:00+00:00')!;
      final b = DateHelpers.parseInstant('2026-11-15T22:30:00+05:30')!;
      expect(a.isUtc, isTrue);
      expect(a, b);
      expect(DateHelpers.parseInstant('nope'), isNull);
      expect(DateHelpers.parseInstant(null), isNull);
    });
  });

  group('local day survives the round trip', () {
    // 22:30 local on 15 Nov in each zone.
    final cases = {
      ist: DateTime.utc(2026, 11, 15, 17),
      pst: DateTime.utc(2026, 11, 16, 6, 30),
    };
    cases.forEach((offset, instant) {
      test('UTC${offset.isNegative ? '' : '+'}${offset.inMinutes / 60}', () {
        final wire = DateHelpers.toUtcIso(instant);
        final back = DateHelpers.parseInstant(wire)!;
        expect(
          DateHelpers.formatLocalIsoDay(back, utcOffset: offset),
          '2026-11-15',
        );
        final wall = DateHelpers.wallClock(back, utcOffset: offset);
        expect((wall.hour, wall.minute), (22, 30));
      });
    });

    test('just after midnight IST is still the previous UTC day', () {
      final instant = DateTime.utc(2026, 11, 14, 18, 45); // 00:15 IST on 15th
      expect(
        DateHelpers.formatLocalIsoDay(instant, utcOffset: ist),
        '2026-11-15',
      );
      expect(
        DateHelpers.formatLocalIsoDay(instant, utcOffset: Duration.zero),
        '2026-11-14',
      );
    });
  });

  group('formatRelative', () {
    final now = DateTime.utc(2026, 11, 15, 12); // 17:30 IST

    test('past', () {
      expect(
        DateHelpers.formatRelative(
          now.subtract(const Duration(seconds: 10)),
          now: now,
          utcOffset: ist,
        ),
        'Just now',
      );
      expect(
        DateHelpers.formatRelative(
          now.subtract(const Duration(minutes: 5)),
          now: now,
          utcOffset: ist,
        ),
        '5 mins ago',
      );
      expect(
        DateHelpers.formatRelative(
          now.subtract(const Duration(hours: 3)),
          now: now,
          utcOffset: ist,
        ),
        '3 hours ago',
      );
      // 23:00 IST the day before.
      expect(
        DateHelpers.formatRelative(
          DateTime.utc(2026, 11, 14, 17, 30),
          now: now,
          utcOffset: ist,
        ),
        'Yesterday',
      );
    });

    test('future instants are never "Just now"', () {
      expect(
        DateHelpers.formatRelative(
          now.add(const Duration(seconds: 30)),
          now: now,
          utcOffset: ist,
        ),
        'Later today',
      );
      expect(
        DateHelpers.formatRelative(
          now.add(const Duration(days: 1)),
          now: now,
          utcOffset: ist,
        ),
        'Tomorrow',
      );
      expect(
        DateHelpers.formatRelative(
          now.add(const Duration(days: 10)),
          now: now,
          utcOffset: ist,
        ),
        isNot('Just now'),
      );
    });

    test('day boundaries follow the local zone', () {
      // 02:00 UTC on the 15th is 18:00 on the 14th in PST.
      final instant = DateTime.utc(2026, 11, 15, 2);
      final later = DateTime.utc(2026, 11, 15, 9); // 01:00 PST on the 15th
      expect(
        DateHelpers.formatRelative(instant, now: later, utcOffset: pst),
        'Yesterday',
      );
      expect(
        DateHelpers.formatRelative(instant, now: later, utcOffset: ist),
        '7 hours ago',
      );
    });
  });

  group('sectionHeader', () {
    final now = DateTime.utc(2026, 11, 15, 12);
    test('today, yesterday, weekday, date', () {
      expect(DateHelpers.sectionHeader(now, now: now, utcOffset: ist), 'Today');
      expect(
        DateHelpers.sectionHeader(
          now.subtract(const Duration(days: 1)),
          now: now,
          utcOffset: ist,
        ),
        'Yesterday',
      );
      expect(
        DateHelpers.sectionHeader(
          now.add(const Duration(days: 1)),
          now: now,
          utcOffset: ist,
        ),
        'Tomorrow',
      );
      expect(
        DateHelpers.sectionHeader(
          DateTime.utc(2026, 11, 12, 12),
          now: now,
          utcOffset: ist,
        ),
        'Thursday',
      );
      expect(
        DateHelpers.sectionHeader(
          DateTime.utc(2026, 10, 1, 12),
          now: now,
          utcOffset: ist,
        ),
        'October 1',
      );
      expect(
        DateHelpers.sectionHeader(
          DateTime.utc(2025, 10, 1, 12),
          now: now,
          utcOffset: ist,
        ),
        'October 1, 2025',
      );
    });
  });

  group('DeviceTimeZone fallback', () {
    test('maps offsets to IANA zones', () {
      expect(DeviceTimeZone.fallbackForOffset(ist), 'Asia/Kolkata');
      expect(DeviceTimeZone.fallbackForOffset(Duration.zero), 'UTC');
      expect(
        DeviceTimeZone.fallbackForOffset(const Duration(hours: 2)),
        'Etc/GMT-2',
      );
      expect(DeviceTimeZone.fallbackForOffset(pst), 'Etc/GMT+8');
      expect(
        DeviceTimeZone.fallbackForOffset(const Duration(hours: 5, minutes: 45)),
        'Asia/Kathmandu',
      );
    });

    test('read() falls back when the plugin is missing', () async {
      final zone = await DeviceTimeZone.read(now: DateTime.now());
      expect(zone, isNotEmpty);
    });
  });
}
