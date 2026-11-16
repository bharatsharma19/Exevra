import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_palette.dart';

/// Draws an [AppPalette.focusRing] outline over the [ListTile] inside [child]
/// that has keyboard or D-pad focus.
///
/// For screens whose rows the app does not build itself, such as Flutter's
/// licence page: a raw [ListTile] only gets the [ThemeData.focusColor] ink
/// tint, which cannot reach 3:1 against the page without pushing the row's
/// secondary text under 4.5:1 on it (see focus_indicator_test). Kit widgets
/// wrap their own rows in a FocusOutline instead.
///
/// The ring is drawn just inside the focused tile, clipped to the list it
/// scrolls in, and follows it while the list scrolls. It only shows in
/// keyboard highlight mode, not after a touch, and controls that draw their
/// own ring (buttons) are left alone.
class FocusRingOverlay extends StatefulWidget {
  /// Creates the overlay around [child].
  const FocusRingOverlay({
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.width = 2,
    super.key,
  });

  /// The screen whose list tiles get the ring.
  final Widget child;

  /// Corner radius of the ring; match the tiles' shape.
  final BorderRadius borderRadius;

  /// Ring width.
  final double width;

  @override
  State<FocusRingOverlay> createState() => _FocusRingOverlayState();
}

class _FocusRingOverlayState extends State<FocusRingOverlay> {
  final _scope = FocusNode(
    debugLabel: 'FocusRingOverlay',
    canRequestFocus: false,
    skipTraversal: true,
  );

  /// The ring and the area it is clipped to, in this widget's coordinates.
  ({Rect ring, Rect clip})? _ring;
  bool _queued = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_queueUpdate);
    FocusManager.instance.addHighlightModeListener(_onHighlightMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_queueUpdate);
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    _scope.dispose();
    super.dispose();
  }

  void _onHighlightMode(FocusHighlightMode _) => _queueUpdate();

  /// Measures after the next layout, when the focused tile has its place.
  void _queueUpdate() {
    if (_queued || !mounted) return;
    _queued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted) return;
      final ring = _measure();
      if (ring != _ring) setState(() => _ring = ring);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  ({Rect ring, Rect clip})? _measure() {
    final manager = FocusManager.instance;
    final focus = manager.primaryFocus;
    final focusContext = focus?.context;
    if (manager.highlightMode != FocusHighlightMode.traditional ||
        focus == null ||
        focusContext == null ||
        !focus.ancestors.contains(_scope) ||
        focusContext.findAncestorWidgetOfExactType<ListTile>() == null) {
      return null;
    }
    final mine = context.findRenderObject();
    final tile = focusContext.findRenderObject();
    if (mine is! RenderBox ||
        tile is! RenderBox ||
        !mine.attached ||
        !tile.attached ||
        !tile.hasSize) {
      return null;
    }
    Rect toLocal(RenderBox box) => MatrixUtils.transformRect(
      box.getTransformTo(mine),
      Offset.zero & box.size,
    );
    var clip = Offset.zero & mine.size;
    final scrollable = Scrollable.maybeOf(
      focusContext,
    )?.context.findRenderObject();
    if (scrollable is RenderBox && scrollable.attached && scrollable.hasSize) {
      clip = clip.intersect(toLocal(scrollable));
    }
    if (clip.isEmpty) return null;
    return (ring: toLocal(tile), clip: clip);
  }

  @override
  Widget build(BuildContext context) {
    final ring = _ring;
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _queueUpdate();
        return false;
      },
      child: Focus(
        focusNode: _scope,
        includeSemantics: false,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (ring != null)
              Positioned.fromRect(
                rect: ring.clip,
                child: IgnorePointer(
                  child: ClipRect(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fromRect(
                          rect: ring.ring.shift(-ring.clip.topLeft),
                          child: DecoratedBox(
                            key: const ValueKey('focus-ring'),
                            decoration: BoxDecoration(
                              borderRadius: widget.borderRadius,
                              border: Border.all(
                                color: context.palette.focusRing,
                                width: widget.width,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
