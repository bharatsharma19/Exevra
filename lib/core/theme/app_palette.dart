import 'package:flutter/material.dart';

part 'app_palette_values.dart';

/// Semantic colour tokens for Exevra, available on every [ThemeData] built by
/// `AppTheme` as a [ThemeExtension].
///
/// Read them with `context.palette` (see [AppPaletteContext]). Widgets must use
/// these tokens or the [ColorScheme] instead of raw colours, so both themes stay
/// readable. `test/design_system/contrast_test.dart` checks every text token at
/// 4.5:1 and every component or chart colour at 3:1 (WCAG 2.x).
///
/// The bright cyan brand accent (`#00E5FF`) is only used in the dark theme. The
/// light theme uses a deep cyan (`#0E7490`) so accent text and icons stay
/// legible on near-white surfaces.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  /// Creates a palette. Prefer [AppPalette.light] and [AppPalette.dark].
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.surfaceElevated,
    required this.outline,
    required this.outlineVariant,
    required this.outlineStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.textOnAccent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.onDangerContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.positiveAmount,
    required this.negativeAmount,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.inverseAccent,
    required this.shimmerBase,
    required this.shimmerHighlight,
    required this.scrim,
    required this.focusRing,
    required this.chart,
    required this.onChart,
    required this.categories,
    required this.categoryFallback,
  });

  /// Brightness of the theme this palette belongs to.
  final Brightness brightness;

  /// Page background behind every surface (scaffold, status/navigation bar).
  final Color background;

  /// Default surface for cards, lists and the navigation bar.
  final Color surface;

  /// Subtle surface for inputs, chips, skeletons and grouped rows.
  final Color surfaceVariant;

  /// Raised surface for dialogs, bottom sheets and menus.
  final Color surfaceElevated;

  /// Boundary of interactive components (inputs, chips, outlined buttons). At least 3:1 against [surface].
  final Color outline;

  /// Decorative hairline for dividers and card borders. Not used to identify a control, so it is exempt from the 3:1 rule.
  final Color outlineVariant;

  /// High-emphasis boundary (selected or hovered component, switch thumb).
  final Color outlineStrong;

  /// Primary text and icons.
  final Color textPrimary;

  /// Supporting text (subtitles, labels, captions).
  final Color textSecondary;

  /// Lowest-emphasis text (hints, timestamps, disabled labels). Still at least 4.5:1.
  final Color textTertiary;

  /// Brand accent for primary actions, links, selected icons and focus. Safe as text and icon colour on every surface of its theme.
  final Color accent;

  /// Text and icons drawn on [accent] (primary buttons, FAB, spinners on primary buttons).
  final Color textOnAccent;

  /// Low-emphasis accent fill (selected chip, navigation indicator).
  final Color accentContainer;

  /// Text and icons drawn on [accentContainer].
  final Color onAccentContainer;

  /// Secondary brand colour (AI features, second chart series).
  final Color secondary;

  /// Text and icons drawn on [secondary].
  final Color onSecondary;

  /// Low-emphasis secondary fill.
  final Color secondaryContainer;

  /// Text and icons drawn on [secondaryContainer].
  final Color onSecondaryContainer;

  /// Success text and icons on surfaces.
  final Color success;

  /// Text and icons drawn on [success].
  final Color onSuccess;

  /// Success fill (badges, snackbars).
  final Color successContainer;

  /// Text and icons drawn on [successContainer].
  final Color onSuccessContainer;

  /// Warning text and icons on surfaces.
  final Color warning;

  /// Text and icons drawn on [warning].
  final Color onWarning;

  /// Warning fill (badges, banners).
  final Color warningContainer;

  /// Text and icons drawn on [warningContainer].
  final Color onWarningContainer;

  /// Error and destructive text and icons on surfaces.
  final Color danger;

  /// Text and icons drawn on [danger] (destructive buttons).
  final Color onDanger;

  /// Error fill (badges, snackbars, banners).
  final Color dangerContainer;

  /// Text and icons drawn on [dangerContainer].
  final Color onDangerContainer;

  /// Informational text and icons on surfaces.
  final Color info;

  /// Text and icons drawn on [info].
  final Color onInfo;

  /// Informational fill (badges, snackbars).
  final Color infoContainer;

  /// Text and icons drawn on [infoContainer].
  final Color onInfoContainer;

  /// Money coming in or owed to the user.
  final Color positiveAmount;

  /// Money going out or owed by the user.
  final Color negativeAmount;

  /// Inverted surface (default snackbar, tooltip).
  final Color inverseSurface;

  /// Text and icons drawn on [inverseSurface].
  final Color onInverseSurface;

  /// Accent used on [inverseSurface] (snackbar actions).
  final Color inverseAccent;

  /// Skeleton placeholder fill.
  final Color shimmerBase;

  /// Moving highlight of the skeleton shimmer.
  final Color shimmerHighlight;

  /// Modal barrier colour behind dialogs and sheets.
  final Color scrim;

  /// Keyboard and input focus indicator. At least 3:1 against [surface] and [background].
  final Color focusRing;

  /// Categorical chart palette: eight hues, each at least 3:1 against
  /// [surface] and 4.5:1 against [onChart]. Index with [chartColor].
  ///
  /// The order matters: neighbouring series and the first five colours stay
  /// distinguishable under simulated deuteranopia and protanopia
  /// (`contrast_test.dart`). Colour alone still cannot carry meaning: every
  /// chart must also label its slices, bars or legend entries with text.
  final List<Color> chart;

  /// Text and icons drawn on any [chart] or [categories] colour (for example
  /// percentage labels inside pie slices). At least 4.5:1 on each of them.
  final Color onChart;

  /// Stable colour per expense category, keyed by the category names in
  /// `AppConstants.categories`. Read it with [categoryColor] so a category
  /// keeps its colour regardless of list order or filtering. Each colour is
  /// at least 3:1 against [surface] and 4.5:1 against [onChart]. Pair the
  /// colour with the category icon and name; never rely on colour alone.
  final Map<String, Color> categories;

  /// Colour for categories missing from [categories].
  final Color categoryFallback;

  /// Whether this is the dark palette.
  bool get isDark => brightness == Brightness.dark;

  /// Chart colour for series [index], wrapping around the palette.
  Color chartColor(int index) => chart[index % chart.length];

  /// Colour of expense [category] (case-insensitive), or [categoryFallback].
  Color categoryColor(String category) {
    final exact = categories[category];
    if (exact != null) return exact;
    final lower = category.toLowerCase();
    for (final entry in categories.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return categoryFallback;
  }

  /// Palette for the light theme.
  static const AppPalette light = _lightPalette;

  /// Palette for the dark theme.
  static const AppPalette dark = _darkPalette;

  @override
  AppPalette copyWith({
    Brightness? brightness,
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? surfaceElevated,
    Color? outline,
    Color? outlineVariant,
    Color? outlineStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? textOnAccent,
    Color? accentContainer,
    Color? onAccentContainer,
    Color? secondary,
    Color? onSecondary,
    Color? secondaryContainer,
    Color? onSecondaryContainer,
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? danger,
    Color? onDanger,
    Color? dangerContainer,
    Color? onDangerContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? positiveAmount,
    Color? negativeAmount,
    Color? inverseSurface,
    Color? onInverseSurface,
    Color? inverseAccent,
    Color? shimmerBase,
    Color? shimmerHighlight,
    Color? scrim,
    Color? focusRing,
    List<Color>? chart,
    Color? onChart,
    Map<String, Color>? categories,
    Color? categoryFallback,
  }) {
    return AppPalette(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      outline: outline ?? this.outline,
      outlineVariant: outlineVariant ?? this.outlineVariant,
      outlineStrong: outlineStrong ?? this.outlineStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      textOnAccent: textOnAccent ?? this.textOnAccent,
      accentContainer: accentContainer ?? this.accentContainer,
      onAccentContainer: onAccentContainer ?? this.onAccentContainer,
      secondary: secondary ?? this.secondary,
      onSecondary: onSecondary ?? this.onSecondary,
      secondaryContainer: secondaryContainer ?? this.secondaryContainer,
      onSecondaryContainer: onSecondaryContainer ?? this.onSecondaryContainer,
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      onDangerContainer: onDangerContainer ?? this.onDangerContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      positiveAmount: positiveAmount ?? this.positiveAmount,
      negativeAmount: negativeAmount ?? this.negativeAmount,
      inverseSurface: inverseSurface ?? this.inverseSurface,
      onInverseSurface: onInverseSurface ?? this.onInverseSurface,
      inverseAccent: inverseAccent ?? this.inverseAccent,
      shimmerBase: shimmerBase ?? this.shimmerBase,
      shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
      scrim: scrim ?? this.scrim,
      focusRing: focusRing ?? this.focusRing,
      chart: chart ?? this.chart,
      onChart: onChart ?? this.onChart,
      categories: categories ?? this.categories,
      categoryFallback: categoryFallback ?? this.categoryFallback,
    );
  }

  @override
  AppPalette lerp(covariant ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return _lerpPalettes(this, other, t);
  }
}

/// Access to the [AppPalette] of the nearest [Theme].
extension AppPaletteContext on BuildContext {
  /// The palette of the nearest [Theme]. Falls back to [AppPalette.light] or
  /// [AppPalette.dark] (by theme brightness) when the theme was not built by
  /// `AppTheme`, for example in isolated widget tests.
  AppPalette get palette {
    final theme = Theme.of(this);
    return theme.extension<AppPalette>() ??
        (theme.brightness == Brightness.dark
            ? AppPalette.dark
            : AppPalette.light);
  }
}
