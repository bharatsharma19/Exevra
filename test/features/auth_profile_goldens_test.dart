import 'dart:async';

import 'package:alchemist/alchemist.dart';
import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:expense_manager/features/auth/screens/login_screen.dart';
import 'package:expense_manager/features/profile/screens/profile_screen.dart';
import 'package:expense_manager/providers/app_lock_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design_system/kit_gallery.dart';
import '../support/fakes.dart';

class _Lock extends AppLockController {
  @override
  AppLockState build() =>
      const AppLockState(availability: LockAvailability.available);
}

Future<void> _settleFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Alchemist CI goldens of the login and Profile screens in both themes.
/// Regenerate with
/// `flutter test --update-goldens test/features/auth_profile_goldens_test.dart`.
void main() {
  late ProviderContainer signedOut;
  late ProviderContainer signedIn;

  setUpAll(() async {
    signedOut = await TestBackend().container();
    final backend = TestBackend(signedInAs: 'u1');
    backend.profiles.profiles['u1'] = profileOf('u1');
    signedIn = await backend.container(
      extraOverrides: [appLockProvider.overrideWith(_Lock.new)],
    );
  });

  tearDownAll(() {
    signedOut.dispose();
    signedIn.dispose();
  });

  final themes = [('light', AppTheme.light()), ('dark', AppTheme.dark())];

  unawaited(
    goldenTest(
      'login renders in light and dark',
      fileName: 'login_screen',
      pumpBeforeTest: _settleFrames,
      builder: () => GoldenTestGroup(
        columns: 2,
        children: [
          for (final (name, theme) in themes)
            GoldenTestScenario(
              name: name,
              constraints: BoxConstraints.tight(const Size(360, 760)),
              child: UncontrolledProviderScope(
                container: signedOut,
                child: ThemedFrame(theme: theme, child: const LoginScreen()),
              ),
            ),
        ],
      ),
    ),
  );

  unawaited(
    goldenTest(
      'profile renders in light and dark',
      fileName: 'profile_screen',
      pumpBeforeTest: _settleFrames,
      builder: () => GoldenTestGroup(
        columns: 2,
        children: [
          for (final (name, theme) in themes)
            GoldenTestScenario(
              name: name,
              constraints: BoxConstraints.tight(const Size(360, 1400)),
              child: UncontrolledProviderScope(
                container: signedIn,
                child: ThemedFrame(theme: theme, child: const ProfileScreen()),
              ),
            ),
        ],
      ),
    ),
  );
}
