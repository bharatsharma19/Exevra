import 'package:flutter/widgets.dart';

import '../theme/app_tokens.dart';

/// Grows [child] to at least a 48 x 48 dp touch target, keeping it centred.
///
/// Use it around small custom controls (icons with a [GestureDetector], text
/// links) that do not get Material's padded tap target.
class MinTapTarget extends StatelessWidget {
  /// Creates a minimum touch target around [child].
  const MinTapTarget({
    required this.child,
    this.size = AppSizes.minTapTarget,
    super.key,
  });

  /// The control.
  final Widget child;

  /// Minimum width and height. Defaults to 48.
  final double size;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: size, minHeight: size),
      child: Center(widthFactor: 1, heightFactor: 1, child: child),
    );
  }
}
