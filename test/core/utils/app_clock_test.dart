import 'dart:io';

import 'package:clock/clock.dart';
import 'package:expense_manager/core/utils/app_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the override fixes now until it is reset', () {
    final fixed = DateTime(2026, 11, 16, 12);
    AppClock.debugOverride = Clock.fixed(fixed);
    addTearDown(() => AppClock.debugOverride = null);
    expect(AppClock.now(), fixed);
    AppClock.debugOverride = null;
    expect(AppClock.now(), isNot(fixed));
  });

  test('a zone clock applies when nothing is overridden', () {
    final fixed = DateTime(2030);
    expect(withClock(Clock.fixed(fixed), AppClock.now), fixed);
  });

  // Goldens and time-dependent tests fix "now" through AppClock, which
  // only works if the app reads the time there.
  test('lib reads the time through AppClock only', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('app_clock.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        // A unique id may use the real clock.
        if (line.contains('microsecondsSinceEpoch')) continue;
        if (line.contains('DateTime.now()')) {
          offenders.add('${file.path}:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
