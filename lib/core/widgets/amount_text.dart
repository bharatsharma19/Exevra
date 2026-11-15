import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_palette.dart';

/// Direction of a money amount.
enum AmountSign {
  /// Money coming in or owed to the user. Shown with "+" in
  /// [AppPalette.positiveAmount].
  positive,

  /// Money going out or owed by the user. Shown with "−" in
  /// [AppPalette.negativeAmount].
  negative,

  /// No direction (totals). Shown in [AppPalette.textPrimary].
  neutral,
}

/// A money amount coloured by direction, with a visible sign so the
/// direction never relies on colour alone.
///
/// [formatted] is the already formatted, unsigned amount (for example from
/// `CurrencyFormatter.format(amount.abs())`); this widget never formats
/// numbers. Screen readers hear "Plus ₹250.00" or "Minus ₹250.00".
class AmountText extends StatelessWidget {
  /// Creates an amount label.
  const AmountText(
    this.formatted, {
    this.sign = AmountSign.neutral,
    this.style,
    this.showSign = true,
    this.scaleDown = false,
    this.semanticLabel,
    this.textAlign,
    super.key,
  });

  /// Formatted amount without a sign.
  final String formatted;

  /// Direction of the amount.
  final AmountSign sign;

  /// Base text style; the colour is replaced by the sign colour.
  final TextStyle? style;

  /// Whether to prefix "+" or "−".
  final bool showSign;

  /// Shrinks the text to fit its width instead of wrapping (hero totals).
  final bool scaleDown;

  /// Overrides the screen reader label.
  final String? semanticLabel;

  /// Text alignment.
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = context.l10n;
    final (Color color, String prefix, String spoken) = switch (sign) {
      AmountSign.positive => (
        palette.positiveAmount,
        '+',
        l10n.amountPositive(formatted),
      ),
      AmountSign.negative => (
        palette.negativeAmount,
        '−',
        l10n.amountNegative(formatted),
      ),
      AmountSign.neutral => (palette.textPrimary, '', formatted),
    };
    final base = style ?? DefaultTextStyle.of(context).style;
    Widget text = Text(
      showSign ? '$prefix$formatted' : formatted,
      textAlign: textAlign,
      maxLines: scaleDown ? 1 : null,
      softWrap: !scaleDown,
      style: base.copyWith(
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    if (scaleDown) {
      text = FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: text,
      );
    }
    return Semantics(
      label: semanticLabel ?? spoken,
      excludeSemantics: true,
      child: text,
    );
  }
}
