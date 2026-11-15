import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat_copy.dart';
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
            label: 'You said',
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
    final label = [
      ChatCopy.assistantName,
      if (message.provider != null) message.provider!.label,
    ].join(' · ');
    final hasText = message.text.trim().isNotEmpty;
    final notice = switch (message.status) {
      ChatMessageStatus.interrupted => ChatCopy.interrupted,
      ChatMessageStatus.stopped => ChatCopy.stopped,
      ChatMessageStatus.truncated => ChatCopy.truncated,
      _ => null,
    };

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
          message: ChatCopy.error(
            message.errorCode,
            serverMessage: message.serverMessage,
          ),
          onRetry: isLast && message.canRetry ? onRetry : null,
        )
      else if (message.isStreaming && !hasText)
        const _Typing()
      else
        SafeMarkdown(data: message.text),
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
    final usable = message.hasUsableText;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onRetry != null)
          IconButton(
            tooltip: 'Retry',
            icon: Icon(Icons.refresh_rounded, color: scheme.primary),
            onPressed: onRetry,
          ),
        if (usable)
          IconButton(
            tooltip: 'Copy message',
            icon: Icon(Icons.copy_rounded, color: scheme.onSurfaceVariant),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: message.text));
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Copied')));
              }
            },
          ),
        if (usable)
          IconButton(
            tooltip: 'Report response',
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
                label: const Text('Retry'),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text('Thinking…', style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
