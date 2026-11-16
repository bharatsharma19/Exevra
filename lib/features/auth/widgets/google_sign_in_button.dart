import 'package:flutter/material.dart';

import '../../../core/accessibility/focus_outline.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../l10n/l10n.dart';

/// "Continue with Google", drawn to Google's sign-in branding guidelines:
/// the full-colour "G" on a white (light theme) or near-black (dark theme)
/// pill with a grey stroke and the label in Roboto Medium.
///
/// The button is 48 dp tall, reads as one button to screen readers, shows
/// a spinner in place of the logo while [isLoading], and draws the app's
/// focus ring when focused from the keyboard.
class GoogleSignInButton extends StatelessWidget {
  /// Creates the button.
  const GoogleSignInButton({
    required this.onPressed,
    this.isLoading = false,
    this.label,
    super.key,
  });

  /// Starts Google sign-in; null disables the button.
  final VoidCallback? onPressed;

  /// Shows a spinner and ignores taps.
  final bool isLoading;

  /// Label; defaults to "Continue with Google".
  final String? label;

  @override
  Widget build(BuildContext context) {
    final dark = context.palette.isDark;
    final fill = dark
        ? GoogleBrandColors.darkFill
        : GoogleBrandColors.lightFill;
    final stroke = dark
        ? GoogleBrandColors.darkStroke
        : GoogleBrandColors.lightStroke;
    final labelColor = dark
        ? GoogleBrandColors.darkLabel
        : GoogleBrandColors.lightLabel;
    final enabled = onPressed != null && !isLoading;
    final text = label ?? context.l10n.authContinueWithGoogle;
    const shape = StadiumBorder();

    return FocusOutline(
      borderRadius: AppRadius.pillAll,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: text,
        excludeSemantics: true,
        child: Opacity(
          // Guidelines: a disabled button keeps its colours at 38% opacity.
          opacity: onPressed == null && !isLoading ? 0.38 : 1,
          child: Material(
            color: fill,
            shape: shape.copyWith(side: BorderSide(color: stroke)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              customBorder: shape,
              // The label colour moves the fill away from the label in both
              // variants only slightly; 6% keeps the label over 12:1.
              overlayColor: WidgetStatePropertyAll(
                labelColor.withValues(alpha: 0.06),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppSizes.minTapTarget,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox.square(
                        dimension: 20,
                        child: isLoading
                            ? CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: labelColor,
                              )
                            : const CustomPaint(painter: GoogleLogoPainter()),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Flexible(
                        child: Text(
                          text,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                            height: 1.3,
                            color: labelColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the full-colour Google "G" logo, scaled to its size (the logo's
/// own 48 x 48 grid).
class GoogleLogoPainter extends CustomPainter {
  /// Creates the painter.
  const GoogleLogoPainter();

  // Google's published "G" logo, as SVG path data on a 48 x 48 grid.
  static const List<(Color, String)> _parts = [
    (
      GoogleBrandColors.red,
      'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 '
          '14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 '
          '9.5z',
    ),
    (
      GoogleBrandColors.blue,
      'M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 '
          '5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z',
    ),
    (
      GoogleBrandColors.yellow,
      'M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19'
          'C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z',
    ),
    (
      GoogleBrandColors.green,
      'M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 '
          '2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 '
          '24 48z',
    ),
  ];

  static final List<(Color, Path)> _paths = [
    for (final (color, data) in _parts) (color, parseSvgPath(data)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / 48, size.height / 48);
    for (final (color, path) in _paths) {
      canvas.drawPath(path, Paint()..color = color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(GoogleLogoPainter oldDelegate) => false;
}

/// Parses the subset of SVG path data the logo uses (M, L, H, V, C, S and
/// Z, absolute and relative).
Path parseSvgPath(String data) {
  final tokens = RegExp(
    r'[MmLlHhVvCcSsZz]|-?(?:\d+\.?\d*|\.\d+)',
  ).allMatches(data).map((m) => m.group(0)!).toList();
  final path = Path();
  var i = 0;
  var command = 'M';
  var x = 0.0;
  var y = 0.0;
  var startX = 0.0;
  var startY = 0.0;
  // Second control point of the last curve, for S.
  double? lastCx;
  double? lastCy;
  double next() => double.parse(tokens[i++]);
  bool isCommand(String t) => RegExp('^[A-Za-z]').hasMatch(t);

  while (i < tokens.length) {
    if (isCommand(tokens[i])) command = tokens[i++];
    final relative = command == command.toLowerCase();
    final dx = relative ? x : 0.0;
    final dy = relative ? y : 0.0;
    switch (command.toUpperCase()) {
      case 'M':
        x = dx + next();
        y = dy + next();
        startX = x;
        startY = y;
        path.moveTo(x, y);
        // Further pairs after a move are line-tos.
        command = relative ? 'l' : 'L';
        lastCx = null;
      case 'L':
        x = dx + next();
        y = dy + next();
        path.lineTo(x, y);
        lastCx = null;
      case 'H':
        x = dx + next();
        path.lineTo(x, y);
        lastCx = null;
      case 'V':
        y = (relative ? y : 0.0) + next();
        path.lineTo(x, y);
        lastCx = null;
      case 'C':
        final x1 = dx + next();
        final y1 = dy + next();
        final x2 = dx + next();
        final y2 = dy + next();
        x = dx + next();
        y = dy + next();
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCx = x2;
        lastCy = y2;
      case 'S':
        final x1 = lastCx == null ? x : 2 * x - lastCx;
        final y1 = lastCy == null || lastCx == null ? y : 2 * y - lastCy;
        final x2 = dx + next();
        final y2 = dy + next();
        x = dx + next();
        y = dy + next();
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCx = x2;
        lastCy = y2;
      case 'Z':
        path.close();
        x = startX;
        y = startY;
        lastCx = null;
      default:
        throw FormatException('Unsupported path command $command');
    }
  }
  return path;
}
