import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Names from the template the app was started from, and copy it no longer
/// uses. None of them may come back into the app or its native shells.
final _banned = RegExp(
  r'antigravity|alex\.mercer|telemetry|Intelligent Financial',
  caseSensitive: false,
);

/// What ships: the Dart code, the native Android and iOS projects and the
/// package manifest.
const _roots = ['lib', 'android/app/src', 'ios/Runner', 'pubspec.yaml'];

Iterable<File> _files() sync* {
  for (final root in _roots) {
    final type = FileSystemEntity.typeSync(root);
    if (type == FileSystemEntityType.file) {
      yield File(root);
    } else if (type == FileSystemEntityType.directory) {
      yield* Directory(
        root,
      ).listSync(recursive: true, followLinks: false).whereType<File>();
    }
  }
}

void main() {
  test('no template branding in lib, the native projects or pubspec', () {
    final hits = <String>[];
    var textFiles = 0;
    for (final file in _files()) {
      final path = file.path.replaceAll(r'\', '/');
      if (_banned.hasMatch(path)) hits.add('$path (path)');
      final String text;
      try {
        text = utf8.decode(file.readAsBytesSync());
      } on FormatException {
        continue; // Images and other binary files.
      }
      textFiles++;
      final lines = const LineSplitter().convert(text);
      for (var i = 0; i < lines.length; i++) {
        final match = _banned.firstMatch(lines[i]);
        if (match != null) hits.add('$path:${i + 1}: "${match[0]}"');
      }
    }
    // The scan ran from the package root and read the sources.
    expect(textFiles, greaterThan(50));
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('the pattern catches each banned name in any case', () {
    for (final sample in [
      'com.antigravity.app',
      'AntiGravity',
      'alex.mercer@example.com',
      'Telemetry',
      'Your intelligent financial companion',
    ]) {
      expect(_banned.hasMatch(sample), isTrue, reason: sample);
    }
    expect(_banned.hasMatch('Exevra'), isFalse);
  });
}
