import 'package:flutter/material.dart';

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
  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFF1F5F9),
    surfaceElevated: Color(0xFFFFFFFF),
    outline: Color(0xFF7C8799),
    outlineVariant: Color(0xFFE2E8F0),
    outlineStrong: Color(0xFF475569),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textTertiary: Color(0xFF5B6B80),
    accent: Color(0xFF0E7490),
    textOnAccent: Color(0xFFFFFFFF),
    accentContainer: Color(0xFFCFFAFE),
    onAccentContainer: Color(0xFF164E63),
    secondary: Color(0xFF6D28D9),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFEDE9FE),
    onSecondaryContainer: Color(0xFF4C1D95),
    success: Color(0xFF047857),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFD1FAE5),
    onSuccessContainer: Color(0xFF064E3B),
    warning: Color(0xFFA3470A),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFEF3C7),
    onWarningContainer: Color(0xFF78350F),
    danger: Color(0xFFB91C1C),
    onDanger: Color(0xFFFFFFFF),
    dangerContainer: Color(0xFFFEE2E2),
    onDangerContainer: Color(0xFF7F1D1D),
    info: Color(0xFF1D4ED8),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFDBEAFE),
    onInfoContainer: Color(0xFF1E3A8A),
    positiveAmount: Color(0xFF047857),
    negativeAmount: Color(0xFFBE123C),
    inverseSurface: Color(0xFF1E293B),
    onInverseSurface: Color(0xFFF1F5F9),
    inverseAccent: Color(0xFF67E8F9),
    shimmerBase: Color(0xFFE2E8F0),
    shimmerHighlight: Color(0xFFF8FAFC),
    scrim: Color(0x73000000),
    focusRing: Color(0xFF0E7490),
    chart: <Color>[
      Color(0xFF0E7490),
      Color(0xFFB45309),
      Color(0xFF7C3AED),
      Color(0xFF047857),
      Color(0xFF1E40AF),
      Color(0xFF4D7C0F),
      Color(0xFFC026D3),
      Color(0xFFB91C1C),
    ],
    onChart: Color(0xFFFFFFFF),
    categories: <String, Color>{
      'Food': Color(0xFFB45309),
      'Transport': Color(0xFF1D4ED8),
      'Housing': Color(0xFF7C3AED),
      'Entertainment': Color(0xFFBE185D),
      'Healthcare': Color(0xFF047857),
      'Utilities': Color(0xFF0E7490),
      'Shopping': Color(0xFFC2410C),
      'Personal': Color(0xFF4338CA),
      'Education': Color(0xFF4D7C0F),
      'Other': Color(0xFF475569),
    },
    categoryFallback: Color(0xFF475569),
  );

  /// Palette for the dark theme.
  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF070B14),
    surface: Color(0xFF0F172A),
    surfaceVariant: Color(0xFF1E293B),
    surfaceElevated: Color(0xFF162033),
    outline: Color(0xFF64748B),
    outlineVariant: Color(0xFF263247),
    outlineStrong: Color(0xFF94A3B8),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFFCBD5E1),
    textTertiary: Color(0xFF94A3B8),
    accent: Color(0xFF00E5FF),
    textOnAccent: Color(0xFF04141C),
    accentContainer: Color(0xFF083344),
    onAccentContainer: Color(0xFFA5F3FC),
    secondary: Color(0xFFA78BFA),
    onSecondary: Color(0xFF1E1B4B),
    secondaryContainer: Color(0xFF2E1065),
    onSecondaryContainer: Color(0xFFDDD6FE),
    success: Color(0xFF34D399),
    onSuccess: Color(0xFF022C22),
    successContainer: Color(0xFF052E22),
    onSuccessContainer: Color(0xFFA7F3D0),
    warning: Color(0xFFFBBF24),
    onWarning: Color(0xFF2A1A03),
    warningContainer: Color(0xFF3B2A06),
    onWarningContainer: Color(0xFFFDE68A),
    danger: Color(0xFFF87171),
    onDanger: Color(0xFF450A0A),
    dangerContainer: Color(0xFF4C0D0D),
    onDangerContainer: Color(0xFFFECACA),
    info: Color(0xFF60A5FA),
    onInfo: Color(0xFF0B1A33),
    infoContainer: Color(0xFF172554),
    onInfoContainer: Color(0xFFBFDBFE),
    positiveAmount: Color(0xFF34D399),
    negativeAmount: Color(0xFFFB7185),
    inverseSurface: Color(0xFFF1F5F9),
    onInverseSurface: Color(0xFF0F172A),
    inverseAccent: Color(0xFF0E7490),
    shimmerBase: Color(0xFF1E293B),
    shimmerHighlight: Color(0xFF334155),
    scrim: Color(0xB3000000),
    focusRing: Color(0xFF67E8F9),
    chart: <Color>[
      Color(0xFF22D3EE),
      Color(0xFFFBBF24),
      Color(0xFFA78BFA),
      Color(0xFF34D399),
      Color(0xFFF472B6),
      Color(0xFFA3E635),
      Color(0xFF60A5FA),
      Color(0xFFFB923C),
    ],
    onChart: Color(0xFF04141C),
    categories: <String, Color>{
      'Food': Color(0xFFFBBF24),
      'Transport': Color(0xFF60A5FA),
      'Housing': Color(0xFFA78BFA),
      'Entertainment': Color(0xFFF472B6),
      'Healthcare': Color(0xFF34D399),
      'Utilities': Color(0xFF22D3EE),
      'Shopping': Color(0xFFFB923C),
      'Personal': Color(0xFF818CF8),
      'Education': Color(0xFFA3E635),
      'Other': Color(0xFF94A3B8),
    },
    categoryFallback: Color(0xFF94A3B8),
  );

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
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: c(background, other.background),
      surface: c(surface, other.surface),
      surfaceVariant: c(surfaceVariant, other.surfaceVariant),
      surfaceElevated: c(surfaceElevated, other.surfaceElevated),
      outline: c(outline, other.outline),
      outlineVariant: c(outlineVariant, other.outlineVariant),
      outlineStrong: c(outlineStrong, other.outlineStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      accent: c(accent, other.accent),
      textOnAccent: c(textOnAccent, other.textOnAccent),
      accentContainer: c(accentContainer, other.accentContainer),
      onAccentContainer: c(onAccentContainer, other.onAccentContainer),
      secondary: c(secondary, other.secondary),
      onSecondary: c(onSecondary, other.onSecondary),
      secondaryContainer: c(secondaryContainer, other.secondaryContainer),
      onSecondaryContainer: c(onSecondaryContainer, other.onSecondaryContainer),
      success: c(success, other.success),
      onSuccess: c(onSuccess, other.onSuccess),
      successContainer: c(successContainer, other.successContainer),
      onSuccessContainer: c(onSuccessContainer, other.onSuccessContainer),
      warning: c(warning, other.warning),
      onWarning: c(onWarning, other.onWarning),
      warningContainer: c(warningContainer, other.warningContainer),
      onWarningContainer: c(onWarningContainer, other.onWarningContainer),
      danger: c(danger, other.danger),
      onDanger: c(onDanger, other.onDanger),
      dangerContainer: c(dangerContainer, other.dangerContainer),
      onDangerContainer: c(onDangerContainer, other.onDangerContainer),
      info: c(info, other.info),
      onInfo: c(onInfo, other.onInfo),
      infoContainer: c(infoContainer, other.infoContainer),
      onInfoContainer: c(onInfoContainer, other.onInfoContainer),
      positiveAmount: c(positiveAmount, other.positiveAmount),
      negativeAmount: c(negativeAmount, other.negativeAmount),
      inverseSurface: c(inverseSurface, other.inverseSurface),
      onInverseSurface: c(onInverseSurface, other.onInverseSurface),
      inverseAccent: c(inverseAccent, other.inverseAccent),
      shimmerBase: c(shimmerBase, other.shimmerBase),
      shimmerHighlight: c(shimmerHighlight, other.shimmerHighlight),
      scrim: c(scrim, other.scrim),
      focusRing: c(focusRing, other.focusRing),
      chart: <Color>[
        for (var i = 0; i < chart.length; i++)
          c(chart[i], other.chart[i % other.chart.length]),
      ],
      onChart: c(onChart, other.onChart),
      categories: <String, Color>{
        for (final entry in categories.entries)
          entry.key: c(entry.value, other.categoryColor(entry.key)),
      },
      categoryFallback: c(categoryFallback, other.categoryFallback),
    );
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
