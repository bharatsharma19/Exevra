import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../data/ai/ai_chat_models.dart';
import '../../../l10n/l10n.dart';

/// The message field with Send, or Stop while an answer streams.
class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    required this.controller,
    required this.streaming,
    required this.onSend,
    required this.onStop,
    super.key,
  });

  final TextEditingController controller;
  final bool streaming;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canSend = controller.text.trim().isNotEmpty && !streaming;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              maxLength: AiChatRequest.maxUserMessageLength,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              // The counter appears only close to the limit.
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    required maxLength,
                  }) => maxLength != null && currentLength > maxLength - 200
                  ? Text(l10n.chatCharacterCount(currentLength, maxLength))
                  : null,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) {
                if (canSend) onSend();
              },
              decoration: InputDecoration(
                hintText: l10n.chatInputHint,
                hintMaxLines: 1,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          if (streaming)
            IconButton.filledTonal(
              tooltip: l10n.chatStop,
              icon: const Icon(Icons.stop_rounded),
              onPressed: onStop,
            )
          else
            IconButton.filled(
              tooltip: l10n.chatSend,
              icon: const Icon(Icons.send_rounded),
              onPressed: canSend ? onSend : null,
            ),
        ],
      ),
    );
  }
}
