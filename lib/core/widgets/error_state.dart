import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import 'state_layout.dart';

/// Full-area error with a Retry button.
///
/// [message] must already be user-friendly: callers pass
/// `friendlyMessage(failure)`, never a raw exception string. The message is a
/// live region, so screen readers announce it when it appears.
class ErrorState extends StatelessWidget {
  /// Creates an error state.
  const ErrorState({
    required this.message,
    this.onRetry,
    this.title,
    this.retryLabel,
    this.icon = Icons.error_outline,
    super.key,
  });

  /// User-facing explanation of what went wrong.
  final String message;

  /// Retry callback. The button is hidden when null.
  final VoidCallback? onRetry;

  /// Headline. Defaults to "Something went wrong".
  final String? title;

  /// Retry button label. Defaults to "Retry".
  final String? retryLabel;

  /// Decorative icon.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    return StateLayout(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StateIcon(
            icon: icon,
            background: palette.dangerContainer,
            foreground: palette.onDangerContainer,
          ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            header: true,
            child: Text(
              title ?? l10n.errorTitle,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(
                color: palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(retryLabel ?? l10n.retry),
            ),
          ],
        ],
      ),
    );
  }
}
