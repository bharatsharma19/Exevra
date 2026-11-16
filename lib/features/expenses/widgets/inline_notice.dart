import 'package:flutter/material.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';

/// The tone of an [InlineNotice].
enum NoticeKind {
  /// Neutral explanation (why an option is unavailable).
  info,

  /// Something to check before saving.
  warning,

  /// A failed action.
  error,

  /// The item cannot change (someone in it left the group).
  locked,
}

/// A short message inside a form or card, with an icon and a container
/// colour pair, so its tone never depends on colour alone. Errors and
/// warnings are live regions: screen readers announce them when they appear.
class InlineNotice extends StatelessWidget {
  /// Creates a notice.
  const InlineNotice({
    required this.message,
    this.kind = NoticeKind.info,
    super.key,
  });

  /// User-facing text.
  final String message;

  /// Tone and icon.
  final NoticeKind kind;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (Color background, Color foreground, IconData icon) = switch (kind) {
      NoticeKind.info => (
        palette.infoContainer,
        palette.onInfoContainer,
        Icons.info_outline_rounded,
      ),
      NoticeKind.warning => (
        palette.warningContainer,
        palette.onWarningContainer,
        Icons.warning_amber_rounded,
      ),
      NoticeKind.error => (
        palette.dangerContainer,
        palette.onDangerContainer,
        Icons.error_outline_rounded,
      ),
      NoticeKind.locked => (
        palette.surfaceVariant,
        palette.textPrimary,
        Icons.lock_outline_rounded,
      ),
    };
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: foreground);
    return Semantics(
      liveRegion: kind == NoticeKind.error || kind == NoticeKind.warning,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadius.mdAll,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + AppSpacing.xxs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(icon, size: AppSizes.iconSm, color: foreground),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(message, style: style)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row with friendly copy for a failed load and a Retry button, for
/// cards and list footers where the full-area `ErrorState` is too large.
class CompactRetry extends StatelessWidget {
  /// Creates the row.
  const CompactRetry({required this.error, required this.onRetry, super.key});

  /// What failed; non-[AppFailure] errors get the generic copy.
  final Object error;

  /// Retry callback.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final failure = error is AppFailure
        ? error as AppFailure
        : const AppFailure.unknown();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        children: [
          Semantics(
            liveRegion: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    Icons.error_outline_rounded,
                    size: AppSizes.iconSm,
                    color: palette.danger,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    friendlyMessage(failure),
                    style: TextStyle(color: palette.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: AppSizes.iconSm),
            label: Text(context.l10n.retry),
          ),
        ],
      ),
    );
  }
}
