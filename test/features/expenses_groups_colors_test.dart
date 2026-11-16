import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The expenses and groups screens take colours from `AppPalette` or the
/// `ColorScheme` only, and keep glass effects out of their rows.
void main() {
  const scopes = ['lib/features/expenses', 'lib/features/groups'];
  final banned = <RegExp>[
    RegExp(r'\bColors\.(?!transparent\b)\w+'),
    RegExp(r'0x[fF]{2}[0-9a-fA-F]{6}\b|Color\(0x'),
    RegExp(r'\bAppColors\.'),
    RegExp(r'\bBackdropFilter\b|\bGlassCard\b'),
  ];

  test('expenses and groups use design-system colours only', () {
    final offenders = <String>[];
    var files = 0;
    for (final scope in scopes) {
      for (final file in Directory(scope).listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        files++;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (banned.any((r) => r.hasMatch(line))) {
            offenders.add('${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }
    }
    expect(files, greaterThan(10));
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
