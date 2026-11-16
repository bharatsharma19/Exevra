import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/accessibility/reduce_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../l10n/l10n.dart';
import '../../dashboard/widgets/feature_snackbar.dart';
import '../chat_error_copy.dart';
import '../models/chat_message.dart';
import 'report_sheet.dart';
import 'safe_markdown.dart';

/// One message of the conversation.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isLast,
    required this.onRetry,
  });

  final ChatMessage message;

  /// Retry is offered only on the newest answer.
  final bool isLast;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return message.isUser ? _user(context) : _assistant(context);
  }

  Widget _user(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: const BorderRadiusDirectional.only(
              topStart: Radius.circular(16),
              topEnd: Radius.circular(16),
              bottomStart: Radius.circular(16),
              bottomEnd: Radius.circular(4),
            ),
          ),
          child: Semantics(
            label: context.l10n.chatYouSaid,
            child: SelectableText(
              message.text,
              style: TextStyle(color: scheme.onPrimaryContainer, height: 1.4),
            ),
          ),
        ),
      ),
    );
  }

  Widget _assistant(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final provider = message.provider;
    final label = provider == null
        ? l10n.chatAssistantName
        : l10n.chatAuthorLine(l10n.chatAssistantName, provider.label);
    final hasText = message.text.trim().isNotEmpty;
    final notice = switch (message.status) {
      ChatMessageStatus.interrupted => l10n.chatInterrupted,
      ChatMessageStatus.stopped => l10n.chatStopped,
      ChatMessageStatus.truncated => l10n.chatTruncated,
      _ => null,
    };
    // A decline without the server's own copy is shown in the app's words.
    final text = message.status == ChatMessageStatus.declined && !hasText
        ? l10n.chatDeclinedFallback
        : message.text;

    final content = <Widget>[
      Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 6),
      if (message.status == ChatMessageStatus.error)
        _ErrorCard(
          message: chatErrorText(
            l10n,
            message.errorCode,
            serverMessage: message.serverMessage,
          ),
          onRetry: isLast && message.canRetry ? onRetry : null,
        )
      else if (message.isStreaming && !hasText)
        const _Typing()
      else
        SafeMarkdown(data: text),
      if (notice != null) ...[
        const SizedBox(height: 8),
        Text(
          notice,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
      if (message.status != ChatMessageStatus.error &&
          !message.isStreaming) ...[
        const SizedBox(height: 4),
        _Actions(
          message: message,
          onRetry: isLast && message.canRetry ? onRetry : null,
        ),
      ],
    ];

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.9,
        ),
        child: GestureDetector(
          // Screen readers use the Report button instead; a long-press
          // action on the text would be a too-small target.
          excludeFromSemantics: true,
          onLongPress: message.hasUsableText
              ? () => showReportSheet(context, message)
              : null,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: const BorderRadiusDirectional.only(
                topStart: Radius.circular(16),
                topEnd: Radius.circular(16),
                bottomStart: Radius.circular(4),
                bottomEnd: Radius.circular(16),
              ),
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.message, required this.onRetry});

  final ChatMessage message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final usable = message.hasUsableText;
    return Wrap(
      children: [
        if (onRetry != null)
          IconButton(
            tooltip: l10n.retry,
            icon: Icon(Icons.refresh_rounded, color: scheme.primary),
            onPressed: onRetry,
          ),
        if (usable)
          IconButton(
            tooltip: l10n.chatCopyTooltip,
            icon: Icon(Icons.copy_rounded, color: scheme.onSurfaceVariant),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: message.text));
              if (context.mounted) {
                showFeatureSnackbar(
                  context,
                  l10n.chatCopied,
                  kind: AppSnackbarKind.success,
                );
              }
            },
          ),
        if (usable)
          IconButton(
            tooltip: l10n.chatReportTooltip,
            icon: Icon(Icons.flag_outlined, color: scheme.onSurfaceVariant),
            onPressed: () => showReportSheet(context, message),
          ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.error_outline_rounded,
                  color: scheme.onErrorContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 6),
                  child: Text(
                    message,
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ),
            ],
          ),
          if (onRetry != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onErrorContainer,
                  minimumSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(context.l10n.retry),
              ),
            ),
        ],
      ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The spinner stays still with reduced motion; the text says it all.
    final still = context.reduceMotion;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: still ? 0.75 : null,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Wraps instead of overflowing at large text on narrow screens.
          Flexible(
            child: Text(
              context.l10n.chatThinking,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
