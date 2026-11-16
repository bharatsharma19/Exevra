import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The auth, profile and About screens take colours from `AppPalette` or
/// the `ColorScheme` only: no legacy `AppColors`, no `Colors.*` (except
/// transparent) and no hex literals. Brand colours fixed by third parties
/// live in lib/core/theme/brand_colors.dart.
void main() {
  const scopes = [
    'lib/features/auth',
    'lib/features/profile',
    'lib/features/about',
  ];
  final banned = RegExp(
    r'\bAppColors\.|\bColors\.(?!transparent\b)\w+|Color\(0x|\b0x[fF]{2}[0-9a-fA-F]{6}\b',
  );

  test('auth, profile and About use theme colours only', () {
    final offenders = <String>[];
    for (final scope in scopes) {
      for (final file in Directory(scope).listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (banned.hasMatch(line)) {
            offenders.add('${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('glass surfaces stay out of these screens', () {
    final offenders = <String>[];
    for (final scope in scopes) {
      for (final file in Directory(scope).listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final source = file.readAsStringSync();
        if (source.contains('GlassCard') || source.contains('BackdropFilter')) {
          offenders.add(file.path);
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
