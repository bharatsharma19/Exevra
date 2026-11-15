import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_palette.dart';

/// System status and navigation bar styling that matches the app theme.
///
/// The app bar theme applies [AppSystemUi.styleFor] automatically. Screens
/// without an [AppBar] (auth, lock, onboarding, full-bleed heroes) wrap their
/// content in [SystemUiRegion] so the bar icons stay visible.
abstract final class AppSystemUi {
  /// Overlay style for [palette]: transparent status bar, navigation bar in
  /// the page background colour, and icons that contrast with both (dark
  /// icons on the light theme, light icons on the dark theme).
  static SystemUiOverlayStyle styleFor(AppPalette palette) {
    final iconBrightness = palette.isDark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      // Android: brightness of the icons.
      statusBarIconBrightness: iconBrightness,
      // iOS: brightness of the content behind the status bar.
      statusBarBrightness: palette.brightness,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarColor: palette.background,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: iconBrightness,
      systemNavigationBarContrastEnforced: false,
    );
  }

  /// Overlay style for the theme at [context].
  static SystemUiOverlayStyle of(BuildContext context) =>
      styleFor(context.palette);
}

/// Applies the system bar style for the current theme to the screen area it
/// covers, for screens that have no [AppBar].
///
/// ```dart
/// return SystemUiRegion(child: Scaffold(body: ...));
/// ```
///
/// Pass [brightness] to force a style, for example [Brightness.dark] for a
/// full-bleed dark hero in the light theme.
class SystemUiRegion extends StatelessWidget {
  /// Creates a region that styles the system bars for its subtree.
  const SystemUiRegion({required this.child, this.brightness, super.key});

  /// The screen content.
  final Widget child;

  /// Forces the light or dark style. Defaults to the theme brightness.
  final Brightness? brightness;

  @override
  Widget build(BuildContext context) {
    final palette = switch (brightness) {
      Brightness.dark => AppPalette.dark,
      Brightness.light => AppPalette.light,
      null => context.palette,
    };
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppSystemUi.styleFor(palette),
      child: child,
    );
  }
}
