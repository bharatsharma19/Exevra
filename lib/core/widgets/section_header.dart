import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// A section title with an optional trailing text action ("See all").
///
/// The title is exposed to screen readers as a heading. Both parts wrap
/// instead of overflowing at narrow widths or large text sizes.
class SectionHeader extends StatelessWidget {
  /// Creates a section header.
  const SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.gutter,
      AppSpacing.xl,
      AppSpacing.sm,
      AppSpacing.xs,
    ),
    super.key,
  });

  /// Section title.
  final String title;

  /// Label of the trailing action. Shown only with [onAction].
  final String? actionLabel;

  /// Trailing action callback.
  final VoidCallback? onAction;

  /// Outer padding.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: textTheme.titleMedium?.copyWith(
                  color: context.palette.textPrimary,
                ),
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            Flexible(
              child: TextButton(
                onPressed: onAction,
                child: Text(actionLabel!, textAlign: TextAlign.end),
              ),
            ),
        ],
      ),
    );
  }
}
