import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Reduced-motion preference for the current context.
extension ReduceMotionContext on BuildContext {
  /// True when the user asked the platform to remove or reduce animations
  /// (Android "Remove animations", iOS "Reduce Motion"), or when an
  /// accessibility service such as TalkBack or VoiceOver drives navigation.
  ///
  /// Animated widgets must skip non-essential motion when this is true:
  /// show the end state directly and do not loop.
  bool get reduceMotion =>
      (MediaQuery.maybeDisableAnimationsOf(this) ?? false) ||
      (MediaQuery.maybeAccessibleNavigationOf(this) ?? false);
}

/// A [flutter_animate](https://pub.dev/packages/flutter_animate) [Animate]
/// that respects [ReduceMotionContext.reduceMotion].
///
/// With motion allowed it plays [effects] like [Animate]. With reduced motion
/// it renders the effects at their end value without animating, so entrance
/// effects show the finished widget and looping effects stay still.
///
/// ```dart
/// MotionSafeAnimate(
///   effects: const [FadeEffect(), SlideEffect(begin: Offset(0, 0.1))],
///   child: card,
/// )
/// ```
class MotionSafeAnimate extends StatelessWidget {
  /// Creates a motion-aware [Animate].
  const MotionSafeAnimate({
    required this.child,
    this.effects,
    this.delay,
    this.onPlay,
    this.onComplete,
    super.key,
  });

  /// The animated widget.
  final Widget child;

  /// Effects to play, as for [Animate.effects].
  final List<Effect<dynamic>>? effects;

  /// Delay before the effects start, as for [Animate.delay].
  final Duration? delay;

  /// Called when the animation starts; use `(c) => c.repeat()` to loop. Not
  /// called under reduced motion.
  final AnimateCallback? onPlay;

  /// Called when the animation completes. Not called under reduced motion.
  final AnimateCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) {
      return Animate(effects: effects, autoPlay: false, value: 1, child: child);
    }
    return Animate(
      effects: effects,
      delay: delay,
      onPlay: onPlay,
      onComplete: onComplete,
      child: child,
    );
  }
}

/// Shorthand for wrapping a widget in [MotionSafeAnimate].
extension MotionSafeAnimateExtension on Widget {
  /// Wraps this widget in a [MotionSafeAnimate] with [effects].
  Widget animateSafely({
    List<Effect<dynamic>>? effects,
    Duration? delay,
    AnimateCallback? onPlay,
    Key? key,
  }) => MotionSafeAnimate(
    key: key,
    effects: effects,
    delay: delay,
    onPlay: onPlay,
    child: this,
  );
}
