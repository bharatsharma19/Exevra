import 'package:expense_manager/core/constants/app_constants.dart';
import 'package:expense_manager/features/auth/screens/login_screen.dart';
import 'package:expense_manager/main.dart';
import 'package:expense_manager/models/profile.dart';
import 'package:expense_manager/providers/profile_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// The status and navigation bar styles annotated where Android reads them:
/// the centre of the status bar (top) and of the navigation bar (bottom).
({SystemUiOverlayStyle? top, SystemUiOverlayStyle? bottom}) _annotated(
  WidgetTester tester,
) {
  final view = tester.view;
  final size = view.physicalSize / view.devicePixelRatio;
  final layer = tester.binding.renderViews.first.debugLayer!;
  final x = size.width / 2;
  return (
    top: layer.find<SystemUiOverlayStyle>(
      Offset(x, view.padding.top / view.devicePixelRatio / 2),
    ),
    bottom: layer.find<SystemUiOverlayStyle>(
      Offset(
        x,
        size.height - 1 - view.padding.bottom / view.devicePixelRatio / 2,
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required String theme,
  String? signedInAs,
}) async {
  final backend = TestBackend(signedInAs: signedInAs);
  if (signedInAs != null) {
    // The profile's theme wins once it loads, so it says the same.
    backend.profiles.profiles[signedInAs] = profileOf(
      signedInAs,
    ).copyWith(themeMode: ThemePreference.values.byName(theme));
  }
  final container = (await tester.runAsync(
    () => backend.container(prefs: {AppConstants.keyThemeMode: theme}),
  ))!;
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ExevraApp()),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final (theme, icons) in [
    ('light', Brightness.dark),
    ('dark', Brightness.light),
  ]) {
    group('$theme theme (${icons.name} icons)', () {
      testWidgets(
        'a screen without an app bar gets contrasting system bar icons',
        (tester) async {
          await _pump(tester, theme: theme);
          expect(find.byType(LoginScreen), findsOneWidget);
          expect(find.byType(AppBar), findsNothing);

          final styles = _annotated(tester);
          expect(styles.top, isNotNull);
          expect(styles.top!.statusBarIconBrightness, icons);
          expect(styles.top!.statusBarColor, Colors.transparent);
          expect(styles.bottom, isNotNull);
          expect(styles.bottom!.systemNavigationBarIconBrightness, icons);

          // What the engine was told last frame.
          expect(SystemChrome.latestStyle?.statusBarIconBrightness, icons);
          expect(
            SystemChrome.latestStyle?.systemNavigationBarIconBrightness,
            icons,
          );
        },
      );

      testWidgets('the signed-in home gets contrasting system bar icons', (
        tester,
      ) async {
        await _pump(tester, theme: theme, signedInAs: 'u1');
        expect(find.byType(LoginScreen), findsNothing);

        final styles = _annotated(tester);
        expect(styles.top?.statusBarIconBrightness, icons);
        expect(styles.top?.statusBarColor, Colors.transparent);
        expect(styles.bottom?.systemNavigationBarIconBrightness, icons);
      });
    });
  }

  testWidgets('switching the theme flips the system bar icons', (tester) async {
    final backend = TestBackend();
    final container = (await tester.runAsync(
      () => backend.container(prefs: {AppConstants.keyThemeMode: 'light'}),
    ))!;
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const ExevraApp()),
    );
    await tester.pumpAndSettle();
    expect(_annotated(tester).top?.statusBarIconBrightness, Brightness.dark);

    await tester.runAsync(
      () => container
          .read(themePreferenceProvider.notifier)
          .setLocal(ThemePreference.dark),
    );
    await tester.pumpAndSettle();
    expect(_annotated(tester).top?.statusBarIconBrightness, Brightness.light);
  });
}
