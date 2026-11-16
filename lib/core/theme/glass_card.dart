import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

// The legacy glass look, kept exactly while screens still use GlassCard.
const Color _darkBorder = Color(0x1FFFFFFF);
const Color _lightBorder = Color(0x14000000);

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
            Border.all(color: isDark ? _darkBorder : _lightBorder, width: 1.2),
        gradient:
            gradient ??
            LinearGradient(
              colors: isDark
                  ? const [Color(0x14FFFFFF), Color(0x05FFFFFF)]
                  : const [Color(0xD9FFFFFF), Color(0x99FFFFFF)],
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
