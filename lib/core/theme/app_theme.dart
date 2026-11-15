import 'dart:ui';

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'app_palette.dart';
import 'app_tokens.dart';
import 'app_typography.dart';
import 'system_ui.dart';

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
    const buttonShape = RoundedRectangleBorder(borderRadius: AppRadius.mdAll);
    const buttonPadding = EdgeInsets.symmetric(
      horizontal: AppSpacing.xl,
      vertical: 14,
    );
    final buttonText = text.labelLarge!.copyWith(fontSize: 16);
    const minButton = Size(AppSizes.minTapTarget, AppSizes.minTapTarget);

    // Keyboard and D-pad focus (WCAG 2.4.7): Material's focus overlay is a
    // faint tint, so the themed components get a solid indicator in
    // AppPalette.focusRing (at least 3:1 against the page, see
    // contrast_test). Filled controls get a ring with a gap ([focusRingSide]),
    // outlined controls a thicker border ([focusBorderSide]), toggles
    // (switch, checkbox, radio) a solid halo with their marks redrawn in
    // textOnAccent on top of it, segments an underline, and snackbar actions
    // an inverted fill. Material only reports the focused state while the
    // keyboard drives focus, so touch users never see it.
    //
    // Not covered by the theme: InkWell-based widgets (ListTile, InkWell,
    // the rows of Flutter's licence page) only get the [ThemeData.focusColor]
    // tint, which cannot reach 3:1 against the page without pushing
    // textSecondary on it under 4.5:1. Kit widgets built on them (AppListTile,
    // AppCard, AppNavigationDestination) add a FocusOutline; screens should
    // use those instead of the raw widgets. Screens built by Flutter (the
    // licence page) are wrapped in a FocusRingOverlay.
    final focusRing = focusRingSide(p);
    final focusBorder = focusBorderSide(p);
    bool focused(Set<WidgetState> states) =>
        states.contains(WidgetState.focused) &&
        !states.contains(WidgetState.disabled);
    final focusSide = WidgetStateProperty.resolveWith<BorderSide?>(
      (states) => focused(states) ? focusRing : null,
    );
    // Radial focus halo of switches, checkboxes and radios. Pressed and
    // hovered overlays keep the Material defaults (null falls through).
    final toggleOverlay = WidgetStateProperty.resolveWith<Color?>(
      (states) => focused(states) ? p.focusRing : null,
    );
    // State layer of accent-filled controls. Material's default is the
    // foreground colour, which pulls the fill toward the label: white text on
    // the light accent fell to 4.4:1 when focused and 3.7:1 when pressed (the
    // highlight and splash stack). onAccentContainer moves the fill away from
    // the label in both themes (darker under white text, lighter under the
    // dark text of the dark theme).
    final accentOverlay = p.onAccentContainer;
    // Accent text of text and outlined buttons. Any state layer behind it
    // takes the light accent under 4.5:1 (4.5 on the page, 4.9 on
    // surfaceVariant at rest), so while hovered, focused or pressed the label
    // deepens to onAccentContainer.
    final accentText = WidgetStateProperty.resolveWith<Color?>(
      (states) => states.contains(WidgetState.disabled)
          ? p.textTertiary
          : states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused) ||
                states.contains(WidgetState.pressed)
          ? p.onAccentContainer
          : p.accent,
    );

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
      focusColor: p.focusRing.withValues(alpha: 0.24),
      // Ink state layers of InkWell-based controls (list tiles, chips, the
      // FAB's press). Material's defaults are grey washes that pull light
      // surfaces toward their text (and lift dark ones toward theirs); a
      // faint textPrimary layer keeps every text role at 4.5:1 even with the
      // pressed highlight and splash stacked (see state_contrast_test).
      hoverColor: p.textPrimary.withValues(alpha: _hoverOpacity),
      highlightColor: p.textPrimary.withValues(alpha: _pressOpacity),
      splashColor: p.textPrimary.withValues(alpha: _pressOpacity),
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
              ? focusBorder
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
            side: focused(states) ? focusRing : BorderSide.none,
          ),
        ),
        extendedTextStyle: buttonText,
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
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.textOnAccent,
          overlayColor: accentOverlay,
          disabledBackgroundColor: p.surfaceVariant,
          disabledForegroundColor: p.textTertiary,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: minButton,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: buttonText,
          tapTargetSize: MaterialTapTargetSize.padded,
        ).copyWith(side: focusSide),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          overlayColor: accentOverlay,
          disabledBackgroundColor: p.surfaceVariant,
          disabledForegroundColor: p.textTertiary,
          minimumSize: minButton,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: buttonText,
          tapTargetSize: MaterialTapTargetSize.padded,
        ).copyWith(side: focusSide),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            ButtonStyle(
              foregroundColor: accentText,
              side: WidgetStateBorderSide.resolveWith(
                (states) => focused(states)
                    ? focusBorder
                    : BorderSide(
                        color: states.contains(WidgetState.disabled)
                            ? p.outlineVariant
                            : p.accent,
                        width: 1.2,
                      ),
              ),
            ).merge(
              // Its foregroundColor only seeds the accent state layer; the
              // label colour is accentText above.
              OutlinedButton.styleFrom(
                foregroundColor: p.accent,
                disabledForegroundColor: p.textTertiary,
                minimumSize: minButton,
                padding: buttonPadding,
                shape: buttonShape,
                textStyle: buttonText,
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accent,
          disabledForegroundColor: p.textTertiary,
          minimumSize: minButton,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: buttonShape,
          textStyle: text.labelLarge,
          tapTargetSize: MaterialTapTargetSize.padded,
        ).copyWith(side: focusSide, foregroundColor: accentText),
      ),
      iconButtonTheme: IconButtonThemeData(
        // A selected (toggled) icon button gets a filled accent container with
        // an accent outline, so the state shows even without a selectedIcon.
        // Otherwise the foreground is left to the variant: the theme style
        // applies to IconButton.filled, .filledTonal and .outlined too, and a
        // fixed textSecondary would put the send button's icon on the accent
        // fill at 1.4:1. The scheme's variant defaults (onSurfaceVariant =
        // textSecondary for the standard button, onPrimary on the fill) all
        // meet 3:1.
        style:
            IconButton.styleFrom(
              minimumSize: minButton,
              tapTargetSize: MaterialTapTargetSize.padded,
            ).copyWith(
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? p.textTertiary
                    : states.contains(WidgetState.selected)
                    ? p.onAccentContainer
                    : null,
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => !states.contains(WidgetState.selected)
                    ? null
                    : states.contains(WidgetState.disabled)
                    ? p.surfaceVariant
                    : p.accentContainer,
              ),
              side: WidgetStateProperty.resolveWith(
                (states) => focused(states)
                    ? focusRing
                    : states.contains(WidgetState.selected) &&
                          !states.contains(WidgetState.disabled)
                    ? BorderSide(color: p.accent)
                    : null,
              ),
            ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(minButton),
          // Segments cannot draw their own ring (SegmentedButton forces a
          // plain shape on them), and a solid focus fill would look more
          // selected than the selected segment. So a focused segment keeps
          // its fill and colours, its label gets a thick focusRing underline,
          // and the group border turns into the focus colour.
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? p.accentContainer
                : p.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? p.textTertiary
                : states.contains(WidgetState.selected)
                ? p.onAccentContainer
                : p.textPrimary,
          ),
          textStyle: WidgetStateProperty.resolveWith(
            (states) => focused(states)
                ? text.labelLarge!.copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: p.focusRing,
                    decorationThickness: 3,
                  )
                : text.labelLarge,
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => focused(states)
                ? BorderSide(color: p.focusRing, width: focusRingWidth)
                : BorderSide(color: p.outline),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        overlayColor: toggleOverlay,
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return p.outlineVariant;
          if (focused(states)) return p.textOnAccent;
          return states.contains(WidgetState.selected)
              ? p.textOnAccent
              : p.outlineStrong;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return p.surfaceVariant;
          return states.contains(WidgetState.selected)
              ? p.accent
              : p.surfaceVariant;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (focused(states)) {
            // On the accent track the outline must contrast with the track.
            return states.contains(WidgetState.selected)
                ? p.textOnAccent
                : p.focusRing;
          }
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return states.contains(WidgetState.disabled)
              ? p.outlineVariant
              : p.outline;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        overlayColor: toggleOverlay,
        // While focused the box sits on the focusRing halo, so it is redrawn
        // in textOnAccent (at least 4.5:1 against the halo).
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (states.contains(WidgetState.disabled)
                    ? p.outlineVariant
                    : focused(states)
                    ? p.textOnAccent
                    : p.accent)
              : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.resolveWith(
          (states) => focused(states) ? p.focusRing : p.textOnAccent,
        ),
        // A WidgetStateBorderSide is also resolved for selected boxes; null
        // keeps the default (no border) there.
        side: WidgetStateBorderSide.resolveWith(
          (states) => focused(states) && !states.contains(WidgetState.selected)
              ? BorderSide(color: p.textOnAccent, width: 2)
              : states.contains(WidgetState.selected)
              ? null
              : BorderSide(color: p.outline, width: 2),
        ),
      ),
      radioTheme: RadioThemeData(
        overlayColor: toggleOverlay,
        fillColor: WidgetStateProperty.resolveWith(
          (states) => focused(states)
              ? p.textOnAccent
              : states.contains(WidgetState.selected)
              ? p.accent
              : p.outline,
        ),
      ),
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

/// Frosted-glass card used by the current screens.
///
/// Legacy: new code uses `AppCard` (solid) or `AppCard.glass` (hero surfaces
/// only) from `lib/core/widgets/app_card.dart`. This widget stays until the
/// screens are migrated.
///
/// The backdrop blur is opt-in: it is applied only when [blurSigma] is above
/// zero, because every `BackdropFilter` adds a compositing pass and list rows
/// built from this card dropped frames while scrolling. Pass a [blurSigma]
/// only for a single hero surface. The ink ripple paints above the gradient
/// fill, so taps are visible.
class GlassCard extends StatelessWidget {
  /// Creates a glass card.
  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.blurSigma = 0,
    this.padding,
    this.margin,
    this.border,
    this.gradient,
    this.onTap,
  });

  /// Card content.
  final Widget child;

  /// Corner radius.
  final double borderRadius;

  /// Backdrop blur strength. Zero (the default) skips the blur.
  final double blurSigma;

  /// Padding around [child]. Defaults to 18 on all sides.
  final EdgeInsetsGeometry? padding;

  /// Outer margin.
  final EdgeInsetsGeometry? margin;

  /// Border override.
  final Border? border;

  /// Background gradient override.
  final Gradient? gradient;

  /// Tap handler; adds an ink ripple.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(borderRadius);

    // Ink paints the fill on the Material, so the InkWell ripple shows above
    // it instead of under an opaque Container.
    Widget card = Ink(
      decoration: BoxDecoration(
        borderRadius: radius,
        border:
            border ??
            Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              width: 1.2,
            ),
        gradient:
            gradient ??
            LinearGradient(
              colors: isDark
                  ? [
                      Colors.white.withValues(alpha: 0.08),
                      Colors.white.withValues(alpha: 0.02),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.85),
                      Colors.white.withValues(alpha: 0.60),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(18),
        child: child,
      ),
    );

    if (onTap != null) {
      card = InkWell(borderRadius: radius, onTap: onTap, child: card);
    }

    card = Material(
      type: MaterialType.transparency,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: card,
    );

    if (blurSigma > 0) {
      card = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: card,
        ),
      );
    }

    if (margin != null) {
      card = Padding(padding: margin!, child: card);
    }
    return card;
  }
}
