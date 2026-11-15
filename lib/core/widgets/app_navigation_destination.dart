import 'package:flutter/material.dart';

import '../accessibility/focus_outline.dart';
import '../theme/app_tokens.dart';

/// A [NavigationDestination] with a visible keyboard focus indicator.
///
/// [NavigationBar] paints its focus highlight under the opaque selection
/// indicator and does not resolve the focused state for icons or labels, so
/// the theme alone cannot show which destination has keyboard focus. This
/// wrapper draws an `AppPalette.focusRing` outline around the destination
/// while it has keyboard (or D-pad) focus. Use it in
/// [NavigationBar.destinations] instead of [NavigationDestination].
class AppNavigationDestination extends StatelessWidget {
  /// Creates a navigation destination.
  const AppNavigationDestination({
    required this.icon,
    required this.label,
    this.selectedIcon,
    this.tooltip,
    this.enabled = true,
    super.key,
  });

  /// Icon of the unselected destination.
  final Widget icon;

  /// Icon of the selected destination. Pass a filled variant so selection
  /// does not rely on colour alone.
  final Widget? selectedIcon;

  /// Text label, also read by screen readers.
  final String label;

  /// Tooltip; defaults to [label].
  final String? tooltip;

  /// Whether the destination can be selected.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return FocusOutline(
      borderRadius: AppRadius.lgAll,
      child: NavigationDestination(
        icon: icon,
        selectedIcon: selectedIcon,
        label: label,
        tooltip: tooltip,
        enabled: enabled,
      ),
    );
  }
}
