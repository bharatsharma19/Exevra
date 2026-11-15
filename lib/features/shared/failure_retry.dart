import 'package:flutter/material.dart';

import '../../core/errors/app_failure.dart';
import '../../core/errors/failure_messages.dart';

/// Friendly error copy for [error] with a Retry button. Errors that are not
/// [AppFailure]s are shown with the generic message (never raw text).
///
/// A stop-gap until the design-system error state replaces it.
class FailureRetry extends StatelessWidget {
  const FailureRetry({
    super.key,
    required this.error,
    required this.onRetry,
    this.compact = false,
  });

  final Object error;
  final VoidCallback onRetry;

  /// One row instead of a centred block (for list footers and cards).
  final bool compact;

  String get message => friendlyMessage(
    error is AppFailure ? error as AppFailure : const AppFailure.unknown(),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Text(
      message,
      textAlign: compact ? TextAlign.start : TextAlign.center,
      style: TextStyle(color: scheme.onSurfaceVariant),
    );
    final button = TextButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh_rounded, size: 18),
      label: const Text('Retry'),
    );
    if (compact) {
      return Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(child: text),
          button,
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 40, color: scheme.error),
          const SizedBox(height: 12),
          text,
          const SizedBox(height: 8),
          button,
        ],
      ),
    );
  }
}
