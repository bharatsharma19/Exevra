import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Widgets must take colours from `AppPalette` or the `ColorScheme`. Only
/// the theme (lib/core/theme/) may define raw colours; every other file in
/// lib/ is checked.
void main() {
  const themeDir = 'lib/core/theme/';
  final rawColors = RegExp(r'\bColors\.(?!transparent\b)\w+');
  final hexColors = RegExp(
    r'0x[fF]{2}[0-9a-fA-F]{6}\b|Color\(\s*0x|Color\.from(?:ARGB|RGBO)\(',
  );
  final legacyConstants = RegExp(r'\bAppColors\b');

  test('lib/ outside the theme contains no hard-coded colours', () {
    final offenders = <String>[];
    var files = 0;
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll(r'\', '/');
      if (path.startsWith(themeDir)) continue;
      files++;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (rawColors.hasMatch(line) ||
            hexColors.hasMatch(line) ||
            legacyConstants.hasMatch(line)) {
          offenders.add('$path:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(files, greaterThan(100));
    expect(
      offenders,
      isEmpty,
      reason:
          'Use context.palette or Theme.of(context).colorScheme instead:\n'
          '${offenders.join('\n')}',
    );
  });
}
