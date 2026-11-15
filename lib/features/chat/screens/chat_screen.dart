import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/haptics.dart';
import '../../../data/ai/ai_chat_models.dart';
import '../../../providers/chat_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../shared/failure_retry.dart';
import '../chat_copy.dart';
import '../widgets/consent_view.dart';
import '../widgets/message_bubble.dart';

/// The Exevra Assistant: consent gate, conversation and input.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _notNow = false;

  /// True while the list is scrolled to (near) the newest message; streamed
  /// tokens are followed only then.
  bool _atBottom = true;

  static const double _bottomSlack = 48;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final atBottom = p.pixels >= p.maxScrollExtent - _bottomSlack;
    if (atBottom != _atBottom) setState(() => _atBottom = atBottom);
  }

  void _followIfAtBottom() {
    if (!_atBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _jumpToLatest() {
    setState(() => _atBottom = true);
    if (!_scroll.hasClients) return;
    unawaited(
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      ),
    );
  }

  void _send([String? text]) {
    final query = (text ?? _input.text).trim();
    final chat = ref.read(chatProvider);
    if (query.isEmpty ||
        chat.isStreaming ||
        query.length > AiChatRequest.maxUserMessageLength) {
      return;
    }
    AppHaptics.light();
    if (text == null) _input.clear();
    setState(() => _atBottom = true);
    unawaited(ref.read(chatProvider.notifier).sendMessage(query));
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear conversation?'),
        content: const Text(
          'This deletes the conversation from this device. It cannot be '
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      AppHaptics.medium();
      await ref.read(chatProvider.notifier).clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(chatProvider, (_, _) => _followIfAtBottom());
    final chat = ref.watch(chatProvider);
    final profile = ref.watch(userProfileProvider);
    final profileState = ref.watch(profileProvider);
    final needsConsent =
        profile != null && (!profile.aiConsent || chat.consentRequired);
    final showChat = profile != null && !needsConsent;

    final Widget body;
    if (profile == null) {
      body = profileState.hasError && !profileState.isLoading
          ? Center(
              child: FailureRetry(
                error: profileState.error!,
                onRetry: () => ref.invalidate(profileProvider),
              ),
            )
          : const Center(child: CircularProgressIndicator());
    } else if (needsConsent && !_notNow) {
      body = ChatConsentView(onNotNow: () => setState(() => _notNow = true));
    } else if (needsConsent) {
      body = _AssistantOff(onTurnOn: () => setState(() => _notNow = false));
    } else {
      body = _conversation(context, chat);
    }

    final provider = chat.provider;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(ChatCopy.assistantName),
            if (showChat && provider != null)
              Text(
                'Answers by ${provider.label}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          if (showChat)
            IconButton(
              tooltip: 'Clear conversation',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: chat.messages.isEmpty ? null : _confirmClear,
            ),
        ],
      ),
      body: body,
    );
  }

  Widget _conversation(BuildContext context, ChatState chat) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final messages = chat.messages;
    final last = messages.isEmpty ? null : messages.last;
    final announcement = chat.isStreaming
        ? ChatCopy.responding
        : last != null && !last.isUser
        ? ChatCopy.complete
        : '';

    return SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                if (messages.isEmpty)
                  _EmptyState(onPrompt: _send)
                else
                  ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                    itemCount: messages.length,
                    itemBuilder: (context, i) => MessageBubble(
                      key: ValueKey(messages[i].id),
                      message: messages[i],
                      isLast: i == messages.length - 1,
                      onRetry: () =>
                          unawaited(ref.read(chatProvider.notifier).retry()),
                    ),
                  ),
                if (messages.isNotEmpty && !_atBottom)
                  PositionedDirectional(
                    bottom: 12,
                    end: 12,
                    child: FloatingActionButton.small(
                      heroTag: null,
                      tooltip: 'Jump to latest',
                      onPressed: _jumpToLatest,
                      child: const Icon(Icons.arrow_downward_rounded),
                    ),
                  ),
              ],
            ),
          ),
          Semantics(
            liveRegion: true,
            label: announcement,
            child: const SizedBox(width: double.infinity, height: 0),
          ),
          if (messages.isNotEmpty && !chat.isStreaming)
            _PromptStrip(onPrompt: _send),
          _InputBar(
            controller: _input,
            streaming: chat.isStreaming,
            onSend: _send,
            onStop: () => ref.read(chatProvider.notifier).stop(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              ChatCopy.disclaimer,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPrompt});

  final void Function(String) onPrompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.auto_awesome_outlined,
              size: 40,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            ChatCopy.emptyTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              color: scheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            ChatCopy.emptyBody,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final prompt in AppConstants.aiQuickPrompts)
                ActionChip(
                  label: Text(prompt),
                  onPressed: () => onPrompt(prompt),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            ChatCopy.disclaimer,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptStrip extends StatelessWidget {
  const _PromptStrip({required this.onPrompt});

  final void Function(String) onPrompt;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: AppConstants.aiQuickPrompts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final prompt = AppConstants.aiQuickPrompts[i];
          return Center(
            child: ActionChip(
              label: Text(prompt),
              onPressed: () => onPrompt(prompt),
            ),
          );
        },
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.streaming,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool streaming;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final canSend = controller.text.trim().isNotEmpty && !streaming;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
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
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) {
                if (canSend) onSend();
              },
              decoration: const InputDecoration(
                hintText: 'Ask about your spending…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (streaming)
            IconButton.filledTonal(
              tooltip: 'Stop response',
              icon: const Icon(Icons.stop_rounded),
              onPressed: onStop,
            )
          else
            IconButton.filled(
              tooltip: 'Send message',
              icon: const Icon(Icons.send_rounded),
              onPressed: canSend ? onSend : null,
            ),
        ],
      ),
    );
  }
}

class _AssistantOff extends StatelessWidget {
  const _AssistantOff({required this.onTurnOn});

  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.chat_bubble_outline,
                size: 40,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'The assistant is off',
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You can keep using Exevra without it, and turn it on '
              'whenever you like.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onTurnOn,
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text('Turn on the assistant'),
            ),
          ],
        ),
      ),
    );
  }
}
