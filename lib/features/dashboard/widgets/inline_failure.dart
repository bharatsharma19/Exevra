import 'package:flutter/material.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';

/// A one-line error inside a card ("Couldn't reach Exevra…") with Retry.
///
/// The message is friendly copy for [error] (never raw exception text) and
/// is announced to screen readers when it appears. The Retry button wraps
/// under the message instead of squeezing it at large text sizes.
class InlineFailure extends StatelessWidget {
  const InlineFailure({required this.error, required this.onRetry, super.key});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final failure = error is AppFailure
        ? error as AppFailure
        : const AppFailure.unknown();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.error_outline_rounded,
                size: AppSizes.iconSm,
                color: palette.danger,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  friendlyMessage(failure),
                  style: textTheme.bodyMedium?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.l10n.retry),
          ),
        ),
      ],
    );
  }
}
