import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the store packaging settings that are easy to lose when the
/// native projects are regenerated. Reads the files from disk.
void main() {
  String read(String path) => File(path).readAsStringSync();

  group('Android', () {
    final gradle = read('android/app/build.gradle.kts');
    final manifest = read('android/app/src/main/AndroidManifest.xml');

    test('uses the final application id and pinned SDK levels', () {
      expect(gradle, contains('namespace = "com.exevra.app"'));
      expect(gradle, contains('applicationId = "com.exevra.app"'));
      expect(gradle, contains('compileSdk = 36'));
      expect(gradle, contains('targetSdk = 36'));
      expect(gradle, contains('minSdk = 24'));
      expect(
        File(
          'android/app/src/main/kotlin/com/exevra/app/MainActivity.kt',
        ).readAsStringSync(),
        allOf(
          contains('FlutterFragmentActivity'),
          contains('"exevra/secure_window"'),
          contains('FLAG_SECURE'),
        ),
      );
    });

    test('never signs a release with the debug key by default', () {
      expect(gradle, contains('rootProject.file("key.properties")'));
      expect(gradle, contains('exevra.allowDebugSigningForLocalTesting'));
      expect(gradle, contains('verifyReleaseSigning'));
      expect(
        gradle,
        isNot(contains('signingConfig = signingConfigs.getByName("debug")')),
      );
    });

    test('ships native symbol tables for Play Console', () {
      expect(gradle, contains('debugSymbolLevel = "SYMBOL_TABLE"'));
    });

    test('keeps app data out of backups and blocks cleartext', () {
      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:fullBackupContent="false"'));
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
      expect(
        manifest,
        contains(
          'android:networkSecurityConfig="@xml/network_security_config"',
        ),
      );
      expect(
        read('android/app/src/main/res/xml/network_security_config.xml'),
        isNot(contains('cleartextTrafficPermitted="true"')),
      );
    });

    test('declares no deprecated or unused permissions', () {
      expect(
        manifest,
        isNot(
          contains(
            '<uses-permission android:name="android.permission.USE_FINGERPRINT"',
          ),
        ),
      );
      expect(manifest, isNot(contains('android.permission.VIBRATE')));
    });

    test('registers the auth callback and invite links', () {
      expect(manifest, contains('android:scheme="com.exevra.app"'));
      expect(manifest, contains('android:host="auth-callback"'));
      expect(manifest, contains('android:scheme="exevra"'));
      expect(manifest, contains('android:autoVerify="true"'));
      expect(manifest, contains('flutter_deeplinking_enabled'));
    });
  });

  group('iOS', () {
    final project = read('ios/Runner.xcodeproj/project.pbxproj');
    final info = read('ios/Runner/Info.plist');

    test('uses the final bundle id, iPhone only, iOS 15', () {
      expect(project, isNot(contains('antigravity')));
      expect(
        RegExp(
          r'PRODUCT_BUNDLE_IDENTIFIER = com\.exevra\.app;',
        ).allMatches(project).length,
        3,
      );
      expect(
        RegExp(
          'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;',
        ).allMatches(project).length,
        3,
      );
      expect(project, isNot(contains('TARGETED_DEVICE_FAMILY = "1,2"')));
      expect(project, isNot(contains('IPHONEOS_DEPLOYMENT_TARGET = 13.0')));
      expect(project, contains('PrivacyInfo.xcprivacy in Resources'));
    });

    test('Info.plist has the store-required keys', () {
      expect(info, contains('<key>ITSAppUsesNonExemptEncryption</key>'));
      expect(info, contains('<key>NSFaceIDUsageDescription</key>'));
      expect(info, isNot(contains('NSCameraUsageDescription')));
      expect(info, isNot(contains('NSPhotoLibraryUsageDescription')));
      expect(info, isNot(contains('UISupportedInterfaceOrientations~ipad')));
      expect(info, isNot(contains('Landscape')));
      expect(info, contains(r'$(GOOGLE_REVERSED_CLIENT_ID)'));
      expect(info, contains(r'$(GOOGLE_IOS_CLIENT_ID)'));
    });

    test('takes the universal link host from the build settings', () {
      expect(
        read('ios/Runner/Runner.entitlements'),
        contains(r'<string>applinks:$(EXEVRA_APP_LINK_HOST)</string>'),
      );
      for (final config in ['Debug', 'Release']) {
        expect(
          read('ios/Flutter/$config.xcconfig'),
          contains('EXEVRA_APP_LINK_HOST = exevra.app'),
        );
      }
    });

    test('answers the secure window channel', () {
      expect(
        read('ios/Runner/AppDelegate.swift'),
        allOf(
          contains('"exevra/secure_window"'),
          contains('"setSecure"'),
          contains('engineBridge.applicationRegistrar.messenger()'),
        ),
      );
    });

    test('privacy manifest declares diagnostics but no performance data', () {
      final manifest = read('ios/Runner/PrivacyInfo.xcprivacy');
      expect(manifest, contains('NSPrivacyCollectedDataTypeCrashData'));
      expect(
        manifest,
        contains('NSPrivacyCollectedDataTypeOtherDiagnosticData'),
      );
      expect(
        manifest,
        isNot(contains('NSPrivacyCollectedDataTypePerformanceData')),
      );
    });
  });

  group('Branding', () {
    test('launcher icons come from the generated flat artwork', () {
      final pubspec = read('pubspec.yaml');
      expect(
        pubspec,
        allOf(
          contains('image_path: "assets/branding/icon_full_bleed.png"'),
          contains(
            'adaptive_icon_foreground: "assets/branding/icon_foreground.png"',
          ),
          contains(
            'adaptive_icon_monochrome: "assets/branding/icon_monochrome.png"',
          ),
        ),
      );
      expect(
        File('assets/icons/app_icon_foreground.png').existsSync(),
        isFalse,
      );
    });
  });

  group('CI', () {
    test('defines the required checks with read-only permissions', () {
      final workflow = read('.github/workflows/ci.yml');
      for (final job in [
        'Flutter',
        'Edge Functions',
        'Database',
        'Android release bundle',
      ]) {
        expect(workflow, contains('    name: $job\n'));
      }
      expect(workflow, contains('permissions:\n  contents: read\n'));
      expect(
        workflow,
        contains('--obfuscate --split-debug-info=build/symbols'),
      );
      expect(workflow, contains('rm -f android/key.properties'));
    });
  });
}
