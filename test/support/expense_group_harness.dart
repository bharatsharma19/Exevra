import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:expense_manager/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Light and dark, for tests that run once per theme.
const themeModes = [ThemeMode.light, ThemeMode.dark];

/// The app shell the expenses and groups tests run in: the real themes,
/// the app's localizations and an optional text scale.
Widget themedApp({
  required Widget home,
  ThemeMode mode = ThemeMode.light,
  double textScale = 1,
  GlobalKey<ScaffoldMessengerState>? messengerKey,
}) => MaterialApp(
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: mode,
  scaffoldMessengerKey: messengerKey,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: home,
);

/// Sets a phone-sized logical viewport of [width] x [height] dp.
void setPhoneSize(
  WidgetTester tester, {
  double width = 360,
  double height = 800,
}) {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Text contrast, 48 dp tap targets and labelled tap targets.
Future<void> expectAccessibleScreen(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  handle.dispose();
}

/// Fails when a layout overflow (or any other exception) was reported.
/// Flutter also fails the test on its own; this names the moment.
void expectNoOverflow(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}
