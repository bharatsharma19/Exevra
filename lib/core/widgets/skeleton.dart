import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../accessibility/reduce_motion.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// A placeholder block shown while content loads.
///
/// Sweeps a soft highlight across [AppPalette.shimmerBase]. Under reduced
/// motion (see `context.reduceMotion`) it is a static block. Hidden from
/// screen readers; wrap a group of skeletons in [SkeletonList] or give the
/// region a "Loading…" label.
///
/// The shimmer repeats forever, so tests that render it should use
/// `pump()` instead of `pumpAndSettle()`, or enable reduced motion.
class SkeletonBox extends StatefulWidget {
  /// Creates a placeholder block.
  const SkeletonBox({
    this.width,
    this.height = 16,
    this.borderRadius = AppRadius.smAll,
    super.key,
  });

  /// Creates a round placeholder (avatars).
  const SkeletonBox.circle({required double size, super.key})
    : width = size,
      height = size,
      borderRadius = AppRadius.pillAll;

  /// Width; null fills the available width.
  final double? width;

  /// Height.
  final double height;

  /// Corner radius.
  final BorderRadius borderRadius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.shimmer,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat().ignore();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final reduce = context.reduceMotion;
    return ExcludeSemantics(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: reduce
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.shimmerBase,
                  borderRadius: widget.borderRadius,
                ),
              )
            : AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: widget.borderRadius,
                    gradient: LinearGradient(
                      begin: Alignment(3 * _controller.value - 2, 0),
                      end: Alignment(3 * _controller.value - 1, 0),
                      colors: [
                        palette.shimmerBase,
                        palette.shimmerHighlight,
                        palette.shimmerBase,
                      ],
                      stops: const [0.1, 0.5, 0.9],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// A list-shaped loading placeholder: [itemCount] rows of an optional avatar
/// and two text lines. Announced once to screen readers as "Loading…".
///
/// It never overflows: rows beyond the available height are clipped.
class SkeletonList extends StatelessWidget {
  /// Creates a list placeholder.
  const SkeletonList({
    this.itemCount = 6,
    this.showAvatar = true,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.gutter,
      vertical: AppSpacing.sm,
    ),
    super.key,
  });

  /// Number of placeholder rows.
  final int itemCount;

  /// Whether each row has a round avatar placeholder.
  final bool showAvatar;

  /// Outer padding.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.loading,
      liveRegion: true,
      child: ClipRect(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < itemCount; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Row(
                    children: [
                      if (showAvatar) ...[
                        const SkeletonBox.circle(size: 40),
                        const SizedBox(width: AppSpacing.lg),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FractionallySizedBox(
                              widthFactor: i.isEven ? 0.7 : 0.55,
                              child: const SkeletonBox(height: 14),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            const FractionallySizedBox(
                              widthFactor: 0.4,
                              child: SkeletonBox(height: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      const SkeletonBox(width: 56, height: 14),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
