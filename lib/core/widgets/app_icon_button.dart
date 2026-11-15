import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// An icon button with a required [tooltip], which is also its screen reader
/// label, and a 48 x 48 dp touch target.
class AppIconButton extends StatelessWidget {
  /// Creates an icon button.
  const AppIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.selected = false,
    this.selectedIcon,
    this.iconSize = AppSizes.icon,
    super.key,
  });

  /// The icon.
  final IconData icon;

  /// Tooltip and accessibility label. Describe the action ("Delete expense").
  final String tooltip;

  /// Tap handler; null disables the button.
  final VoidCallback? onPressed;

  /// Icon colour override. Must be a palette or [ColorScheme] colour.
  final Color? color;

  /// Whether the button is in its selected (toggled) state.
  final bool selected;

  /// Icon shown when [selected].
  final IconData? selectedIcon;

  /// Icon size.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: selected,
      iconSize: iconSize,
      constraints: const BoxConstraints(
        minWidth: AppSizes.minTapTarget,
        minHeight: AppSizes.minTapTarget,
      ),
      color: color,
      selectedIcon: selectedIcon == null
          ? null
          : Icon(selectedIcon, color: color ?? palette.accent),
      icon: Icon(icon),
    );
  }
}
