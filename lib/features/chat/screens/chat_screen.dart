import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/haptics.dart';
import '../../../data/ai/ai_chat_models.dart';
import '../../../providers/chat_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../shared/failure_retry.dart';
import '../chat_copy.dart';
import '../chat_theme.dart';
import '../widgets/consent_view.dart';
import '../widgets/message_bubble.dart';

/// The Exevra Assistant: consent gate, conversation and input.
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Everything below, dialogs and sheets included, uses colour roles that
    // reach AA contrast.
    return Theme(
      data: ChatTheme.of(Theme.of(context)),
      child: const _ChatView(),
    );
  }
}

class _ChatView extends ConsumerStatefulWidget {
  const _ChatView();

  @override
  ConsumerState<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<_ChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _notNow = false;

  /// True while the list shows the newest message; streamed tokens are
  /// followed only then. Any user scroll toward older messages clears it.
  bool _atBottom = true;
  ScrollDirection _lastUserDirection = ScrollDirection.idle;
  bool _followQueued = false;

  /// Whether the list has been moved to the newest message since it last
  /// appeared; a restored conversation would otherwise open at the oldest.
  bool _openedAtLatest = false;

  static const double _bottomSlack = 48;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _setAtBottom(bool value) {
    if (value != _atBottom) setState(() => _atBottom = value);
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (n is UserScrollNotification) {
      if (n.direction != ScrollDirection.idle) {
        _lastUserDirection = n.direction;
      }
      // Toward older messages: stop following at once, so a stream never
      // pulls the list out from under the user's finger.
      if (n.direction == ScrollDirection.forward) _setAtBottom(false);
    } else if (n is ScrollEndNotification) {
      final slack = _lastUserDirection == ScrollDirection.forward
          ? 1.0
          : _bottomSlack;
      _setAtBottom(n.metrics.extentAfter <= slack);
    }
    return false;
  }

  void _followIfAtBottom() {
    if (!_atBottom || _followQueued) return;
    _followQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followQueued = false;
      if (!mounted || !_atBottom || !_scroll.hasClients) return;
      final p = _scroll.position;
      // jumpTo would end a drag, fling or the Jump to latest animation.
      if (p.isScrollingNotifier.value ||
          p.userScrollDirection != ScrollDirection.idle) {
        return;
      }
      if (p.pixels < p.maxScrollExtent) _scroll.jumpTo(p.maxScrollExtent);
    });
  }

  /// Puts a list that just appeared at its newest message. A lazy list only
  /// estimates its extent, so this repeats until the end stops moving.
  void _openAtLatest([int attempts = 5]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_atBottom || !_scroll.hasClients) return;
      final p = _scroll.position;
      if (p.isScrollingNotifier.value ||
          p.userScrollDirection != ScrollDirection.idle ||
          p.pixels >= p.maxScrollExtent) {
        return;
      }
      _scroll.jumpTo(p.maxScrollExtent);
      if (attempts > 1) _openAtLatest(attempts - 1);
    });
  }

  void _jumpToLatest() {
    _lastUserDirection = ScrollDirection.idle;
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
    _lastUserDirection = ScrollDirection.idle;
    setState(() => _atBottom = true);
    unawaited(ref.read(chatProvider.notifier).sendMessage(query));
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
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
    if (messages.isEmpty) {
      _openedAtLatest = false;
    } else if (!_openedAtLatest) {
      _openedAtLatest = true;
      _openAtLatest();
    }
    final announcement = chat.isStreaming
        ? ChatCopy.responding
        : last != null && !last.isUser
        ? ChatCopy.complete
        : '';

    final media = MediaQuery.of(context);
    // With the keyboard open or large text, the quick prompts would leave
    // the conversation no room.
    final compact =
        media.viewInsets.bottom > 0 || media.textScaler.scale(14) > 14 * 1.5;

    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  if (messages.isEmpty)
                    _EmptyState(onPrompt: _send)
                  else
                    NotificationListener<ScrollNotification>(
                      onNotification: _onScrollNotification,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                        itemCount: messages.length,
                        itemBuilder: (context, i) => MessageBubble(
                          key: ValueKey(messages[i].id),
                          message: messages[i],
                          isLast: i == messages.length - 1,
                          onRetry: () => unawaited(
                            ref.read(chatProvider.notifier).retry(),
                          ),
                        ),
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
            // A node with no area is dropped from the semantics tree, so
            // the live region needs a size to reach TalkBack.
            Semantics(
              liveRegion: true,
              label: announcement,
              child: const SizedBox(width: double.infinity, height: 1),
            ),
            // The controls never take more than half the height; past that
            // they scroll, so the conversation keeps its share.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight / 2),
              child: SingleChildScrollView(
                reverse: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (messages.isNotEmpty && !chat.isStreaming && !compact)
                      _PromptStrip(onPrompt: _send),
                    _InputBar(
                      controller: _input,
                      streaming: chat.isStreaming,
                      onSend: _send,
                      onStop: () => ref.read(chatProvider.notifier).stop(),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
              ),
            ),
          ],
        ),
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
              // The counter appears only close to the limit.
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    required maxLength,
                  }) => maxLength != null && currentLength > maxLength - 200
                  ? Text('$currentLength/$maxLength')
                  : null,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) {
                if (canSend) onSend();
              },
              decoration: const InputDecoration(
                hintText: 'Ask about your spending…',
                hintMaxLines: 1,
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
      child: SingleChildScrollView(
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
