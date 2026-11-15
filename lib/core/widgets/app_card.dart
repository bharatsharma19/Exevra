import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../accessibility/focus_outline.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// A surface card built from theme tokens.
///
/// The default constructor draws a solid [AppPalette.surface] card with a
/// hairline border. Use it for lists and most content.
///
/// [AppCard.glass] adds a frosted backdrop blur. It is meant for one or two
/// hero surfaces per screen (for example the balance summary); do **not** use
/// it for list items, because every [BackdropFilter] forces an extra
/// compositing pass and scrolling many of them drops frames.
///
/// When [onTap] is set, the card is a button: the ink ripple paints on the
/// card's own [Material] (above the background), so it is visible in both
/// themes, screen readers get a single button node with the card's text, the
/// card is at least 48 dp tall, and keyboard focus draws a focus ring.
class AppCard extends StatelessWidget {
  /// Creates a solid card.
  const AppCard({
    required this.child,
    this.padding = AppSpacing.cardPadding,
    this.margin,
    this.onTap,
    this.onLongPress,
    this.color,
    this.borderRadius = AppRadius.lgAll,
    this.showBorder = true,
    this.semanticLabel,
    super.key,
  }) : _glass = false,
       blurSigma = 0;

  /// Creates a frosted-glass card for hero surfaces only (see class docs).
  const AppCard.glass({
    required this.child,
    this.padding = AppSpacing.cardPadding,
    this.margin,
    this.onTap,
    this.onLongPress,
    this.color,
    this.borderRadius = AppRadius.xlAll,
    this.showBorder = true,
    this.semanticLabel,
    this.blurSigma = 16,
    super.key,
  }) : _glass = true;

  /// Card content.
  final Widget child;

  /// Padding around [child].
  final EdgeInsetsGeometry padding;

  /// Space around the card.
  final EdgeInsetsGeometry? margin;

  /// Makes the whole card tappable.
  final VoidCallback? onTap;

  /// Long-press handler.
  final VoidCallback? onLongPress;

  /// Background override. Must be a palette or [ColorScheme] colour.
  final Color? color;

  /// Corner radius.
  final BorderRadius borderRadius;

  /// Whether to draw the hairline border.
  final bool showBorder;

  /// Screen reader label. A tappable card is read as one button made of this
  /// label (if any) followed by the card's text.
  final String? semanticLabel;

  /// Blur strength of [AppCard.glass].
  final double blurSigma;

  final bool _glass;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final background =
        color ??
        (_glass
            ? palette.surface.withValues(alpha: palette.isDark ? 0.72 : 0.8)
            : palette.surface);
    final shape = RoundedRectangleBorder(
      borderRadius: borderRadius,
      side: showBorder
          ? BorderSide(color: palette.outlineVariant)
          : BorderSide.none,
    );

    final tappable = onTap != null || onLongPress != null;
    Widget content = Padding(padding: padding, child: child);
    if (tappable) {
      content = InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        customBorder: shape,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.minTapTarget),
          child: content,
        ),
      );
    }

    Widget card = Material(
      color: background,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: content,
    );

    if (_glass) {
      card = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: card,
        ),
      );
    }

    if (tappable) {
      card = FocusOutline(borderRadius: borderRadius, child: card);
      // One screen reader node: the action plus the card's text.
      card = MergeSemantics(
        child: Semantics(button: true, label: semanticLabel, child: card),
      );
    } else if (semanticLabel != null) {
      card = Semantics(container: true, label: semanticLabel, child: card);
    }

    if (margin != null) {
      card = Padding(padding: margin!, child: card);
    }
    return card;
  }
}
