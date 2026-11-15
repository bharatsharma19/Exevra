import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// A label on the left and a value on the right ("Paid by" — "Priya").
///
/// Both sides wrap within their half instead of overflowing, and screen
/// readers read the pair as one item.
class KeyValueRow extends StatelessWidget {
  /// Creates a row from text.
  const KeyValueRow({
    required this.label,
    required String this.value,
    this.emphasize = false,
    this.padding = const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    super.key,
  }) : valueWidget = null;

  /// Creates a row with a custom value widget (an [AmountText], a badge).
  const KeyValueRow.custom({
    required this.label,
    required Widget this.valueWidget,
    this.emphasize = false,
    this.padding = const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    super.key,
  }) : value = null;

  /// Left-hand label.
  final String label;

  /// Right-hand text value.
  final String? value;

  /// Right-hand custom value.
  final Widget? valueWidget;

  /// Uses a heavier style for totals.
  final bool emphasize;

  /// Outer padding.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final valueStyle =
        (emphasize ? textTheme.titleMedium : textTheme.bodyMedium)?.copyWith(
          color: palette.textPrimary,
        );
    return MergeSemantics(
      child: Padding(
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: textTheme.bodyMedium?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Flexible(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: DefaultTextStyle.merge(
                  style: valueStyle,
                  textAlign: TextAlign.end,
                  child: valueWidget ?? Text(value!, textAlign: TextAlign.end),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
