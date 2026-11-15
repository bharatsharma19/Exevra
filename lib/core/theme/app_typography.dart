import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Type scale for Exevra.
///
/// Uses the platform system font (Roboto on Android, SF on iOS); no font files
/// are bundled. Sizes follow the Material 3 scale with heavier titles.
abstract final class AppTypography {
  /// Builds the [TextTheme] for [palette]. Colours come from the palette so
  /// every style is readable on its theme's surfaces.
  static TextTheme textTheme(AppPalette palette) {
    final primary = palette.textPrimary;
    final secondary = palette.textSecondary;
    TextStyle style(
      double size,
      double lineHeight,
      FontWeight weight,
      Color color, {
      double letterSpacing = 0,
    }) => TextStyle(
      fontSize: size,
      height: lineHeight / size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: color,
    );

    return TextTheme(
      displayLarge: style(
        57,
        64,
        FontWeight.w400,
        primary,
        letterSpacing: -0.25,
      ),
      displayMedium: style(45, 52, FontWeight.w400, primary),
      displaySmall: style(36, 44, FontWeight.w600, primary),
      headlineLarge: style(
        32,
        40,
        FontWeight.w700,
        primary,
        letterSpacing: -0.5,
      ),
      headlineMedium: style(
        28,
        36,
        FontWeight.w700,
        primary,
        letterSpacing: -0.25,
      ),
      headlineSmall: style(24, 32, FontWeight.w700, primary),
      titleLarge: style(20, 28, FontWeight.w700, primary, letterSpacing: -0.2),
      titleMedium: style(16, 24, FontWeight.w600, primary, letterSpacing: 0.1),
      titleSmall: style(14, 20, FontWeight.w600, primary, letterSpacing: 0.1),
      bodyLarge: style(16, 24, FontWeight.w400, primary, letterSpacing: 0.15),
      bodyMedium: style(14, 20, FontWeight.w400, primary, letterSpacing: 0.25),
      bodySmall: style(12, 16, FontWeight.w400, secondary, letterSpacing: 0.4),
      labelLarge: style(14, 20, FontWeight.w600, primary, letterSpacing: 0.1),
      labelMedium: style(
        12,
        16,
        FontWeight.w600,
        secondary,
        letterSpacing: 0.5,
      ),
      labelSmall: style(11, 16, FontWeight.w600, secondary, letterSpacing: 0.5),
    );
  }
}
