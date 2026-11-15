import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import 'state_layout.dart';

/// Placeholder for a screen or list with no content yet, with an optional
/// call to action ("Add your first expense").
///
/// Fills the available space and scrolls when it does not fit, so it is safe
/// at 320 dp width and 200% text size.
class EmptyState extends StatelessWidget {
  /// Creates an empty state.
  const EmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    super.key,
  });

  /// Decorative icon.
  final IconData icon;

  /// Short headline ("No expenses yet").
  final String title;

  /// Supporting sentence explaining what to do.
  final String? message;

  /// Primary call-to-action label. Shown only with [onAction].
  final String? actionLabel;

  /// Primary call-to-action.
  final VoidCallback? onAction;

  /// Optional icon for the call to action.
  final IconData? actionIcon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return StateLayout(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StateIcon(
            icon: icon,
            background: palette.accentContainer,
            foreground: palette.onAccentContainer,
          ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(
                color: palette.textPrimary,
              ),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onAction,
              icon: Icon(actionIcon ?? Icons.add),
              label: Text(actionLabel!, textAlign: TextAlign.center),
            ),
          ],
        ],
      ),
    );
  }
}
