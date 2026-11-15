import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_tokens.dart';
import 'app_typography.dart';
import 'system_ui.dart';

export 'glass_card.dart';

part 'app_control_themes.dart';

/// Material 3 themes for Exevra, built entirely from [AppPalette] tokens.
///
/// Every [ColorScheme] role is set explicitly (no seed generation), and the
/// components the app uses have themes so screens do not need raw colours.
/// The palette is attached as a [ThemeExtension]; read it with
/// `context.palette`.
class AppTheme {
  AppTheme._();

  static final ThemeData _light = _build(AppPalette.light);
  static final ThemeData _dark = _build(AppPalette.dark);

  /// The light theme.
  static ThemeData light() => _light;

  /// The dark theme.
  static ThemeData dark() => _dark;

  /// Legacy alias of [light], kept while `main.dart` and the screens still
  /// use it. New code calls [light]. It is not marked `@Deprecated` yet
  /// because the analyzer would then fail on the remaining call sites.
  static ThemeData get lightTheme => _light;

  /// Legacy alias of [dark]; see [lightTheme].
  static ThemeData get darkTheme => _dark;

  /// Width of the keyboard focus ring.
  static const double focusRingWidth = 2;

  /// Space between a filled control and its focus ring.
  static const double focusRingGap = 2;

  // Opacities of the ink state layers, as in Material's button defaults.
  static const double _hoverOpacity = 0.08;
  static const double _focusOpacity = 0.1;
  static const double _pressOpacity = 0.1;

  // Ink layers of InkWell-based controls (list tiles, chips, cards, the
  // navigation bar). InkResponse keeps one highlight per state and stacks
  // them, so a keyboard activation paints the focus tint, the pressed
  // highlight and a splash at once, and a mouse press adds both on top of
  // the hover tint. These alphas keep every text role at 4.5:1 and icons at
  // 3:1 under the heaviest stack (see state_contrast_test).
  static const double _inkPressOpacity = 0.06;
  static const double _inkFocusOpacity = 0.12;

  /// Keyboard focus ring for filled and borderless controls (filled,
  /// elevated, destructive, text and icon buttons, the FAB).
  ///
  /// A [focusRingWidth] ring of [AppPalette.focusRing] drawn [focusRingGap]
  /// outside the control, so the page shows between the fill and the ring.
  /// Both edges of the ring then touch the page (at least 3:1, see
  /// contrast_test), and the gap keeps the ring apart from a fill of the same
  /// hue (the light accent equals the light focus ring).
  static BorderSide focusRingSide(AppPalette p) => BorderSide(
    color: p.focusRing,
    width: focusRingWidth,
    // strokeInset = width * (1 - (1 + align) / 2) = -gap.
    strokeAlign: 1 + 2 * focusRingGap / focusRingWidth,
  );

  /// Keyboard focus border for outlined controls (outlined buttons, chips):
  /// their own border turns into a thicker [AppPalette.focusRing] border
  /// drawn outside the control. The colours on both sides of it (the page and
  /// the control's pale fill) are at least 3:1 against the ring.
  static BorderSide focusBorderSide(AppPalette p) => BorderSide(
    color: p.focusRing,
    width: 3,
    strokeAlign: BorderSide.strokeAlignOutside,
  );

  /// Builds the [ColorScheme] for [p]. Exposed for tests.
  static ColorScheme colorSchemeFor(AppPalette p) => ColorScheme(
    brightness: p.brightness,
    primary: p.accent,
    onPrimary: p.textOnAccent,
    primaryContainer: p.accentContainer,
    onPrimaryContainer: p.onAccentContainer,
    secondary: p.secondary,
    onSecondary: p.onSecondary,
    secondaryContainer: p.secondaryContainer,
    onSecondaryContainer: p.onSecondaryContainer,
    tertiary: p.success,
    onTertiary: p.onSuccess,
    tertiaryContainer: p.successContainer,
    onTertiaryContainer: p.onSuccessContainer,
    error: p.danger,
    onError: p.onDanger,
    errorContainer: p.dangerContainer,
    onErrorContainer: p.onDangerContainer,
    surface: p.surface,
    onSurface: p.textPrimary,
    onSurfaceVariant: p.textSecondary,
    surfaceDim: p.background,
    surfaceBright: p.surfaceElevated,
    surfaceContainerLowest: p.isDark ? p.background : p.surface,
    surfaceContainerLow: p.isDark ? p.surface : p.background,
    surfaceContainer: p.isDark ? p.surfaceElevated : p.surfaceVariant,
    surfaceContainerHigh: p.isDark ? p.surfaceElevated : p.surfaceElevated,
    surfaceContainerHighest: p.surfaceVariant,
    outline: p.outline,
    outlineVariant: p.outlineVariant,
    shadow: p.scrim.withValues(alpha: 1),
    scrim: p.scrim.withValues(alpha: 1),
    inverseSurface: p.inverseSurface,
    onInverseSurface: p.onInverseSurface,
    inversePrimary: p.inverseAccent,
    surfaceTint: Colors.transparent,
  );

  static ThemeData _build(AppPalette p) {
    final scheme = colorSchemeFor(p);
    final text = AppTypography.textTheme(p);
    final c = _Controls(p, text);
    final focused = c.focused;
    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[p],
      textTheme: text,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      dividerColor: p.outlineVariant,
      disabledColor: p.textTertiary,
      hintColor: p.textTertiary,
      focusColor: p.focusRing.withValues(alpha: _inkFocusOpacity),
      // Ink state layers of InkWell-based controls (list tiles, chips, the
      // FAB's press). Material's defaults are grey washes that pull light
      // surfaces toward their text (and lift dark ones toward theirs); a
      // faint textPrimary layer keeps every text role at 4.5:1 even with the
      // hover, focus and pressed highlights and the splash stacked (see
      // _inkPressOpacity and state_contrast_test).
      hoverColor: p.textPrimary.withValues(alpha: _hoverOpacity),
      highlightColor: p.textPrimary.withValues(alpha: _inkPressOpacity),
      splashColor: p.textPrimary.withValues(alpha: _inkPressOpacity),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      iconTheme: IconThemeData(color: p.textSecondary, size: AppSizes.icon),
      appBarTheme: AppBarThemeData(
        backgroundColor: p.background,
        foregroundColor: p.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: p.textPrimary),
        actionsIconTheme: IconThemeData(color: p.textPrimary),
        systemOverlayStyle: AppSystemUi.styleFor(p),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // The selected destination does not rely on the pale indicator fill:
        // the indicator has an accent outline (at least 3:1 against the bar),
        // and the icon and label switch to the accent colour and a heavier
        // weight. Screens should also pass a filled `selectedIcon`.
        // Keyboard focus: NavigationBar paints its focus highlight under the
        // opaque indicator and does not resolve the focused state for icons or
        // labels, so the theme cannot draw a visible ring here. Destinations
        // use AppNavigationDestination, which adds the focus outline.
        indicatorColor: p.accentContainer,
        indicatorShape: StadiumBorder(side: BorderSide(color: p.accent)),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: AppSizes.icon,
            color: states.contains(WidgetState.selected)
                ? p.accent
                : p.textSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? text.labelMedium!.copyWith(
                  color: p.accent,
                  fontWeight: FontWeight.w800,
                )
              : text.labelMedium!.copyWith(
                  color: p.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.surface,
        selectedItemColor: p.accent,
        unselectedItemColor: p.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surfaceElevated,
        modalBackgroundColor: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: p.scrim,
        elevation: AppElevation.high,
        modalElevation: AppElevation.high,
        dragHandleColor: p.outline,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        barrierColor: p.scrim,
        elevation: AppElevation.high,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium!.copyWith(color: p.textSecondary),
        iconColor: p.accent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.inverseSurface,
        contentTextStyle: text.bodyMedium!.copyWith(color: p.onInverseSurface),
        // SnackBar gives its action its own TextButtonTheme, so the text
        // button focus ring never reaches it (and focusRing is under 3:1 on
        // inverseSurface anyway). A focused action inverts instead: an
        // onInverseSurface fill with inverseSurface text. AppSnackbar's
        // tinted kinds pass their own colour pair, which inverts the same way.
        actionTextColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? p.onInverseSurface
              : focused(states)
              ? p.inverseSurface
              : p.inverseAccent,
        ),
        actionBackgroundColor: WidgetStateColor.resolveWith(
          (states) => focused(states) ? p.onInverseSurface : Colors.transparent,
        ),
        disabledActionTextColor: p.onInverseSurface,
        closeIconColor: p.onInverseSurface,
        elevation: AppElevation.medium,
        insetPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),
      chipTheme: ChipThemeData(
        color: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? p.accentContainer
              : p.surfaceVariant,
        ),
        side: WidgetStateBorderSide.resolveWith(
          (states) => focused(states)
              ? c.focusBorder
              : BorderSide(
                  color: states.contains(WidgetState.disabled)
                      ? p.outlineVariant
                      : states.contains(WidgetState.selected)
                      ? p.accent
                      : p.outline,
                ),
        ),
        // Chips resolve only the colour of their label style, never a
        // WidgetStateTextStyle itself: one would reach the label with no
        // colour and no size, and the engine paints such text white (1.1:1
        // on the light chip fill). So the style is plain and its colour is
        // the state-dependent part.
        labelStyle: text.labelLarge!.copyWith(
          color: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? p.textTertiary
                : states.contains(WidgetState.selected)
                ? p.onAccentContainer
                : p.textPrimary,
          ),
        ),
        checkmarkColor: p.onAccentContainer,
        iconTheme: IconThemeData(color: p.textSecondary, size: AppSizes.iconSm),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        showCheckmark: true,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.accent,
        foregroundColor: p.textOnAccent,
        // Same accent state layer as filled buttons (see accentOverlay).
        focusColor: p.onAccentContainer.withValues(alpha: _focusOpacity),
        hoverColor: p.onAccentContainer.withValues(alpha: _hoverOpacity),
        splashColor: p.onAccentContainer.withValues(alpha: _pressOpacity),
        elevation: AppElevation.low,
        focusElevation: AppElevation.medium,
        hoverElevation: AppElevation.medium,
        highlightElevation: AppElevation.medium,
        // The FAB has no themeable side, but RawMaterialButton resolves a
        // state-dependent shape, so the focus ring rides on the shape.
        shape: WidgetStateOutlinedBorder.resolveWith(
          (states) => RoundedRectangleBorder(
            borderRadius: AppRadius.lgAll,
            side: focused(states) ? c.focusRing : BorderSide.none,
          ),
        ),
        extendedTextStyle: c.buttonText,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: p.outlineVariant),
        ),
      ),
      listTileTheme: ListTileThemeData(
        minTileHeight: AppSizes.minTapTarget,
        minVerticalPadding: AppSpacing.sm,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        iconColor: p.textSecondary,
        textColor: p.textPrimary,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodyMedium!.copyWith(color: p.textSecondary),
        leadingAndTrailingTextStyle: text.labelLarge!.copyWith(
          color: p.textSecondary,
        ),
        // A theme-level shape cannot vary with selection, so the pale fill is
        // backed by an accent outline in AppListTile; prefer that widget.
        selectedColor: p.onAccentContainer,
        selectedTileColor: p.accentContainer,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: p.surfaceVariant,
        // Not the ink hoverColor above: a textPrimary wash on the field fill
        // pulled the light hint under 4.5:1. A hovered field moves toward
        // the page instead (lighter in light, darker in dark), away from its
        // label, hint and text.
        hoverColor: p.isDark
            ? p.background.withValues(alpha: 0.5)
            : p.surface.withValues(alpha: 0.7),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        border: inputBorder(p.outline),
        enabledBorder: inputBorder(p.outline),
        disabledBorder: inputBorder(p.outlineVariant),
        focusedBorder: inputBorder(p.focusRing, 2),
        errorBorder: inputBorder(p.danger, 1.5),
        focusedErrorBorder: inputBorder(p.danger, 2),
        labelStyle: text.bodyLarge!.copyWith(color: p.textSecondary),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith(
          (states) => text.bodyMedium!.copyWith(
            color: states.contains(WidgetState.error)
                ? p.danger
                : states.contains(WidgetState.focused)
                ? p.accent
                : p.textSecondary,
          ),
        ),
        hintStyle: text.bodyLarge!.copyWith(color: p.textTertiary),
        helperStyle: text.bodySmall!.copyWith(color: p.textSecondary),
        errorStyle: text.bodySmall!.copyWith(color: p.danger),
        errorMaxLines: 3,
        helperMaxLines: 3,
        prefixIconColor: p.textSecondary,
        suffixIconColor: p.textSecondary,
      ),
      elevatedButtonTheme: c.elevatedButtonTheme,
      filledButtonTheme: c.filledButtonTheme,
      outlinedButtonTheme: c.outlinedButtonTheme,
      textButtonTheme: c.textButtonTheme,
      iconButtonTheme: c.iconButtonTheme,
      segmentedButtonTheme: c.segmentedButtonTheme,
      switchTheme: c.switchTheme,
      checkboxTheme: c.checkboxTheme,
      radioTheme: c.radioTheme,
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.surfaceVariant,
        circularTrackColor: Colors.transparent,
        refreshBackgroundColor: p.surfaceElevated,
      ),
      dividerTheme: DividerThemeData(
        color: p.outlineVariant,
        thickness: 1,
        space: AppSpacing.xl,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.inverseSurface,
          borderRadius: AppRadius.smAll,
        ),
        textStyle: text.bodySmall!.copyWith(color: p.onInverseSurface),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        waitDuration: const Duration(milliseconds: 400),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.medium,
        textStyle: text.bodyLarge,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: BorderSide(color: p.outlineVariant),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.accent,
        selectionColor: p.accent.withValues(alpha: 0.3),
        selectionHandleColor: p.accent,
      ),
    );
  }
}
