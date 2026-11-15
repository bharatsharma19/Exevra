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

  /// The light theme. Same as [light].
  static ThemeData get lightTheme => _light;

  /// The dark theme. Same as [dark].
  static ThemeData get darkTheme => _dark;

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
        indicatorColor: p.accentContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: AppSizes.icon,
            color: states.contains(WidgetState.selected)
                ? p.onAccentContainer
                : p.textSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? text.labelMedium!.copyWith(color: p.textPrimary)
              : text.labelMedium!.copyWith(color: p.textSecondary),
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
        actionTextColor: p.inverseAccent,
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
          (states) => BorderSide(
            color: states.contains(WidgetState.disabled)
                ? p.outlineVariant
                : states.contains(WidgetState.selected)
                ? p.accent
                : p.outline,
          ),
        ),
        labelStyle: WidgetStateTextStyle.resolveWith(
          (states) => text.labelLarge!.copyWith(
            color: states.contains(WidgetState.disabled)
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
        elevation: AppElevation.low,
        focusElevation: AppElevation.medium,
        hoverElevation: AppElevation.medium,
        highlightElevation: AppElevation.medium,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
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
          disabledBackgroundColor: p.surfaceVariant,
          disabledForegroundColor: p.textTertiary,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: minButton,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: buttonText,
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          disabledBackgroundColor: p.surfaceVariant,
          disabledForegroundColor: p.textTertiary,
          minimumSize: minButton,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: buttonText,
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            ButtonStyle(
              side: WidgetStateBorderSide.resolveWith(
                (states) => BorderSide(
                  color: states.contains(WidgetState.disabled)
                      ? p.outlineVariant
                      : p.accent,
                  width: 1.2,
                ),
              ),
            ).merge(
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
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: p.textSecondary,
          disabledForegroundColor: p.textTertiary,
          minimumSize: minButton,
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(minButton),
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
          side: WidgetStatePropertyAll(BorderSide(color: p.outline)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return p.outlineVariant;
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
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return states.contains(WidgetState.disabled)
              ? p.outlineVariant
              : p.outline;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (states.contains(WidgetState.disabled)
                    ? p.outlineVariant
                    : p.accent)
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(p.textOnAccent),
        side: BorderSide(color: p.outline, width: 2),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? p.accent : p.outline,
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
class GlassCard extends StatelessWidget {
  /// Creates a glass card.
  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.blurSigma = 14,
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

  /// Backdrop blur strength.
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

    final Widget cardContent = Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(18),
            child: child,
          ),
        ),
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: onTap,
          child: cardContent,
        ),
      );
    }

    return cardContent;
  }
}
