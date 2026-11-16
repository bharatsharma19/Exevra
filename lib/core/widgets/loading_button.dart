import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// Visual weight of a [LoadingButton].
enum LoadingButtonVariant {
  /// Filled accent button for the main action of a screen.
  primary,

  /// Outlined accent button for secondary actions.
  secondary,

  /// Filled danger button for destructive actions (delete, leave group).
  destructive,
}

/// A button that shows a spinner while its action runs.
///
/// While [isLoading] is true the button ignores taps and is reported as
/// disabled to screen readers, but keeps its enabled colours so the spinner
/// (drawn in the button's foreground colour) stays visible in both themes.
/// When [onPressed] is null and it is not loading, the themed disabled style
/// applies.
class LoadingButton extends StatelessWidget {
  /// Creates a loading button.
  const LoadingButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.variant = LoadingButtonVariant.primary,
    this.icon,
    this.expand = true,
    super.key,
  });

  /// Button text. Kept visible while loading so the width does not jump.
  final String label;

  /// Action; null disables the button.
  final VoidCallback? onPressed;

  /// Shows the spinner and ignores taps.
  final bool isLoading;

  /// Visual weight.
  final LoadingButtonVariant variant;

  /// Optional leading icon (hidden while loading).
  final IconData? icon;

  /// Whether the button fills the available width.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // The state layer (hover, focus, press) of a filled variant is its
    // container's "on" colour, not the label colour Material would derive
    // from foregroundColor: that pulled the fill toward the label (white on
    // the light accent fell to 4.4:1 when focused). The on-container colour
    // moves the fill away from the label in both themes, like the theme's
    // filled buttons.
    final (
      Color background,
      Color foreground,
      Color overlay,
    ) = switch (variant) {
      LoadingButtonVariant.primary => (
        palette.accent,
        palette.textOnAccent,
        palette.onAccentContainer,
      ),
      LoadingButtonVariant.secondary => (
        Colors.transparent,
        palette.accent,
        palette.accent,
      ),
      LoadingButtonVariant.destructive => (
        palette.danger,
        palette.onDanger,
        palette.onDangerContainer,
      ),
    };

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isLoading)
          SizedBox.square(
            dimension: AppSizes.buttonSpinner,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: foreground,
              semanticsLabel: context.l10n.loading,
            ),
          )
        else if (icon != null)
          Icon(icon, size: AppSizes.iconSm),
        if (isLoading || icon != null) const SizedBox(width: AppSpacing.sm),
        // No maxLines: at large text sizes the label wraps and the button
        // grows taller instead of clipping words.
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );

    // While loading, pin the enabled colours over the disabled state.
    final loadingStyle = isLoading
        ? ButtonStyle(
            backgroundColor: WidgetStatePropertyAll(background),
            foregroundColor: WidgetStatePropertyAll(foreground),
            side: variant == LoadingButtonVariant.secondary
                ? WidgetStatePropertyAll(BorderSide(color: palette.accent))
                : null,
          )
        : null;
    const sizeStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(AppSizes.minTapTarget, AppSizes.buttonHeight),
      ),
    );
    final callback = isLoading ? null : onPressed;

    final Widget button = switch (variant) {
      LoadingButtonVariant.secondary => OutlinedButton(
        onPressed: callback,
        style: sizeStyle.merge(loadingStyle),
        child: child,
      ),
      LoadingButtonVariant.primary ||
      LoadingButtonVariant.destructive => FilledButton(
        onPressed: callback,
        style: sizeStyle
            .merge(loadingStyle)
            .merge(
              FilledButton.styleFrom(
                backgroundColor: background,
                foregroundColor: foreground,
                overlayColor: overlay,
              ),
            ),
        child: child,
      ),
    };

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
