import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Draws a [AppPalette.focusRing] outline around [child] while a descendant
/// has keyboard or D-pad focus.
///
/// Material's ink focus overlay is a faint tint (well under 3:1 against the
/// surface), so kit widgets built on [InkWell] wrap themselves in this to get
/// a visible focus indicator. The outline only shows in keyboard highlight
/// mode, not after a touch.
class FocusOutline extends StatefulWidget {
  /// Creates a focus outline.
  const FocusOutline({
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.width = 2,
    super.key,
  });

  /// The focusable content (for example an [InkWell]).
  final Widget child;

  /// Corner radius of the outline; match the child's shape.
  final BorderRadius borderRadius;

  /// Outline width.
  final double width;

  @override
  State<FocusOutline> createState() => _FocusOutlineState();
}

class _FocusOutlineState extends State<FocusOutline> {
  bool _focused = false;
  bool _keyboard = _isKeyboard(FocusManager.instance.highlightMode);

  static bool _isKeyboard(FocusHighlightMode mode) =>
      mode == FocusHighlightMode.traditional;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onHighlightMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    super.dispose();
  }

  void _onHighlightMode(FocusHighlightMode mode) {
    final keyboard = _isKeyboard(mode);
    if (keyboard != _keyboard) setState(() => _keyboard = keyboard);
  }

  @override
  Widget build(BuildContext context) {
    final show = _focused && _keyboard;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (focused) {
        if (focused != _focused) setState(() => _focused = focused);
      },
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: show
            ? BoxDecoration(
                borderRadius: widget.borderRadius,
                border: Border.all(
                  color: context.palette.focusRing,
                  width: widget.width,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
              )
            : const BoxDecoration(),
        child: widget.child,
      ),
    );
  }
}
