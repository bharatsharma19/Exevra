import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The app theme with colour roles adjusted so every text role the
/// assistant uses reaches WCAG AA (4.5:1) on the surfaces it is drawn on.
///
/// The app theme leaves the container roles undefined (they fall back to
/// `primary`/`error` with white text, about 3.7:1) and its light primary,
/// error and hint colours are too light for 14sp text. Colours are derived
/// from the theme's own roles, never from literals.
abstract final class ChatTheme {
  /// Minimum contrast aimed for (a little above 4.5 to absorb rounding).
  static const double minContrast = 4.6;

  static ThemeData of(ThemeData base) {
    final s = base.colorScheme;
    final light = s.brightness == Brightness.light;
    final page = base.scaffoldBackgroundColor;
    final fill = _opaque(
      base.inputDecorationTheme.fillColor ?? s.surfaceContainerHighest,
      page,
    );
    final surfaces = [s.surface, page, s.surfaceContainerHigh];

    final primary = ensureContrast(s.primary, [
      ...surfaces,
      s.onPrimary,
    ], toward: s.onSurface);
    final error = ensureContrast(s.error, surfaces, toward: s.onSurface);
    final primaryContainer = Color.lerp(
      s.surface,
      primary,
      light ? 0.12 : 0.28,
    )!;
    final errorContainer = Color.lerp(s.surface, error, light ? 0.10 : 0.25)!;
    final onSurfaceVariant = ensureContrast(s.onSurfaceVariant, [
      ...surfaces,
      fill,
      s.surfaceContainerHighest,
    ], toward: s.onSurface);

    final scheme = s.copyWith(
      primary: primary,
      error: error,
      primaryContainer: primaryContainer,
      onPrimaryContainer: ensureContrast(s.onSurface, [
        primaryContainer,
      ], toward: s.onSurface),
      errorContainer: errorContainer,
      onErrorContainer: ensureContrast(s.onSurface, [
        errorContainer,
      ], toward: s.onSurface),
      onSurfaceVariant: onSurfaceVariant,
    );
    final input = base.inputDecorationTheme;
    return base.copyWith(
      colorScheme: scheme,
      inputDecorationTheme: input.copyWith(
        hintStyle: (input.hintStyle ?? const TextStyle()).copyWith(
          color: onSurfaceVariant,
        ),
        counterStyle: (input.counterStyle ?? const TextStyle()).copyWith(
          color: onSurfaceVariant,
        ),
      ),
    );
  }

  /// WCAG contrast ratio of two opaque colours.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// [color] moved toward [toward] until it reaches [minContrast] on every
  /// colour of [backgrounds] (or as close as it gets).
  static Color ensureContrast(
    Color color,
    List<Color> backgrounds, {
    required Color toward,
  }) {
    bool passes(Color c) =>
        backgrounds.every((b) => contrast(c, b) >= minContrast);
    if (passes(color)) return color;
    for (var step = 1; step <= 20; step++) {
      final candidate = Color.lerp(color, toward, step / 20)!;
      if (passes(candidate)) return candidate;
    }
    return toward;
  }

  static Color _opaque(Color color, Color over) =>
      color.a >= 1 ? color : Color.alphaBlend(color, over);
}
