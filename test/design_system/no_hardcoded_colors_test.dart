import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Widgets must take colours from `AppPalette` or the `ColorScheme`. Only the
/// theme files (lib/core/theme/, lib/core/constants/app_colors.dart) may
/// define raw colours. The scope widens to all of lib/ once the screens are
/// migrated.
void main() {
  const scopes = ['lib/core/widgets', 'lib/core/accessibility'];
  final rawColors = RegExp(r'\bColors\.(?!transparent\b)\w+');
  final hexColors = RegExp(r'0x[fF]{2}[0-9a-fA-F]{6}\b|Color\(0x');

  test('kit sources contain no hard-coded colours', () {
    final offenders = <String>[];
    var files = 0;
    for (final scope in scopes) {
      final dir = Directory(scope);
      expect(dir.existsSync(), isTrue, reason: '$scope is missing');
      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        files++;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (rawColors.hasMatch(line) || hexColors.hasMatch(line)) {
            offenders.add('${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }
    }
    expect(files, greaterThan(0));
    expect(
      offenders,
      isEmpty,
      reason:
          'Use context.palette or Theme.of(context).colorScheme instead:\n'
          '${offenders.join('\n')}',
    );
  });
}
