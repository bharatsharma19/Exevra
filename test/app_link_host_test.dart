import 'dart:io';

import 'package:expense_manager/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Invite links must point at the host the Android app claims, so both
/// come from APP_LINK_HOST with the same default.
void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();

  test('the manifest takes the invite host from the build', () {
    expect(manifest, contains(r'android:host="${appLinkHost}"'));
    expect(manifest, isNot(contains('exevra.com')));
  });

  test('the Android default host matches AppConfig', () {
    expect(gradle, contains('dartDefines["APP_LINK_HOST"]'));
    expect(gradle, contains('?: "${AppConfig.defaultAppLinkHost}"'));
    expect(gradle, contains('manifestPlaceholders["appLinkHost"]'));
  });

  test('lib/ builds invite links only through AppConfig', () {
    final offenders = [
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart') &&
            RegExp(
              r'https://[a-z0-9.-]+/invite',
            ).hasMatch(file.readAsStringSync()))
          file.path,
    ];
    expect(offenders, isEmpty);
  });
}
