import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Decorative round icon used by the empty and error states.
class StateIcon extends StatelessWidget {
  /// Creates a round icon badge.
  const StateIcon({
    required this.icon,
    required this.background,
    required this.foreground,
    super.key,
  });

  /// The icon.
  final IconData icon;

  /// Circle fill.
  final Color background;

  /// Icon colour.
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Icon(icon, size: AppSizes.iconLg - 8, color: foreground),
        ),
      ),
    );
  }
}

/// Centres [child] and lets it scroll when the available height is too small
/// (short screens, large text).
class StateLayout extends StatelessWidget {
  /// Creates the layout.
  const StateLayout({required this.child, super.key});

  /// The state content (a column).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padded = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xl,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: child,
      ),
    );
    // Centred when it fits; scrolls when the height is too small. Works in
    // bounded and unbounded parents and supports intrinsic sizing.
    return Center(child: SingleChildScrollView(child: padded));
  }
}
