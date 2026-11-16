import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/accessibility/reduce_motion.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/ai/ai_chat_models.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/chat_provider.dart';
import '../../../providers/profile_provider.dart';
import '../chat_error_copy.dart';
import '../widgets/assistant_off_view.dart';
import '../widgets/chat_empty_view.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/consent_view.dart';
import '../widgets/message_bubble.dart';

/// What screen readers hear when an answer ends with [message]: success
/// says "Response complete"; a failed, declined, stopped, interrupted or
/// cut-short answer says so instead.
String chatOutcomeAnnouncement(AppLocalizations l10n, ChatMessage? message) {
  if (message == null || message.isUser) return '';
  return switch (message.status) {
    ChatMessageStatus.done => l10n.chatAnnounceComplete,
    ChatMessageStatus.truncated => l10n.chatAnnounceTruncated,
    ChatMessageStatus.declined => l10n.chatAnnounceDeclined,
    ChatMessageStatus.stopped => l10n.chatAnnounceStopped,
    ChatMessageStatus.interrupted => l10n.chatAnnounceInterrupted,
    ChatMessageStatus.streaming => l10n.chatResponding,
    ChatMessageStatus.error => l10n.chatAnnounceFailed(
      chatErrorText(
        l10n,
        message.errorCode,
        serverMessage: message.serverMessage,
      ),
    ),
  };
}

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

  /// True while the list shows the newest message; streamed tokens are
  /// followed only then. Any user scroll toward older messages clears it.
  bool _atBottom = true;
  ScrollDirection _lastUserDirection = ScrollDirection.idle;
  bool _followQueued = false;

  /// Whether the list has been moved to the newest message since it last
  /// appeared; a restored conversation would otherwise open at the oldest.
  bool _openedAtLatest = false;

  /// Height the conversation had at the last layout. When it shrinks (the
  /// keyboard opens) the newest message is kept in view.
  double? _lastHeight;

  /// Read by screen readers as a live region: "Assistant is responding",
  /// then how the answer ended. Empty until something happens, so opening
  /// a saved conversation announces nothing.
  String _announcement = '';

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
    final end = _scroll.position.maxScrollExtent;
    if (context.reduceMotion) {
      _scroll.jumpTo(end);
      return;
    }
    unawaited(
      _scroll.animateTo(
        end,
        duration: AppDurations.medium,
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
    final l10n = context.l10n;
    final ok = await showConfirmDialog(
      context,
      title: l10n.chatClearTitle,
      message: l10n.chatClearMessage,
      confirmLabel: l10n.chatClearConfirm,
      destructive: true,
    );
    if (ok && mounted) {
      AppHaptics.medium();
      await ref.read(chatProvider.notifier).clear();
    }
  }

  void _onChatChanged(ChatState? previous, ChatState next) {
    _followIfAtBottom();
    final wasStreaming = previous?.isStreaming ?? false;
    final String announcement;
    if (next.isStreaming && !wasStreaming) {
      announcement = context.l10n.chatResponding;
    } else if (wasStreaming && !next.isStreaming) {
      announcement = chatOutcomeAnnouncement(
        context.l10n,
        next.messages.isEmpty ? null : next.messages.last,
      );
    } else if (next.messages.isEmpty) {
      announcement = '';
    } else {
      return;
    }
    if (announcement != _announcement) {
      setState(() => _announcement = announcement);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    ref.listen(chatProvider, _onChatChanged);
    final chat = ref.watch(chatProvider);
    final profile = ref.watch(userProfileProvider);
    final profileState = ref.watch(profileProvider);
    final needsConsent =
        profile != null && (!profile.aiConsent || chat.consentRequired);
    final showChat = profile != null && !needsConsent;

    final Widget body;
    if (profile == null) {
      final error = profileState.error;
      body = profileState.hasError && !profileState.isLoading
          ? ErrorState(
              message: friendlyMessage(
                error is AppFailure ? error : const AppFailure.unknown(),
              ),
              onRetry: () => ref.invalidate(profileProvider),
            )
          : Semantics(
              label: l10n.loading,
              child: const SkeletonList(itemCount: 3),
            );
    } else if (needsConsent && !_notNow) {
      body = ChatConsentView(onNotNow: () => setState(() => _notNow = true));
    } else if (needsConsent) {
      body = AssistantOffView(onTurnOn: () => setState(() => _notNow = false));
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
            Text(l10n.chatAssistantName),
            if (showChat && provider != null)
              Text(
                l10n.chatAnswersBy(provider.label),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          if (showChat)
            AppIconButton(
              tooltip: l10n.chatClearTooltip,
              icon: Icons.delete_sweep_outlined,
              onPressed: chat.messages.isEmpty
                  ? null
                  : () => unawaited(_confirmClear()),
            ),
        ],
      ),
      body: body,
    );
  }

  Widget _conversation(BuildContext context, ChatState chat) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final messages = chat.messages;
    if (messages.isEmpty) {
      _openedAtLatest = false;
    } else if (!_openedAtLatest) {
      _openedAtLatest = true;
      _openAtLatest();
    }

    final media = MediaQuery.of(context);
    // With the keyboard open or large text, the quick prompts would leave
    // the conversation no room.
    final compact =
        media.viewInsets.bottom > 0 || media.textScaler.scale(14) > 14 * 1.5;

    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (_lastHeight != constraints.maxHeight) {
            // The keyboard opened or closed: keep the newest message in
            // view when the user was reading it.
            if (_lastHeight != null) _followIfAtBottom();
            _lastHeight = constraints.maxHeight;
          }
          return Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    if (messages.isEmpty)
                      ChatEmptyView(onPrompt: _send)
                    else
                      NotificationListener<ScrollNotification>(
                        onNotification: _onScrollNotification,
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            AppSpacing.sm,
                            AppSpacing.md,
                            AppSpacing.lg,
                          ),
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
                        bottom: AppSpacing.md,
                        end: AppSpacing.md,
                        child: FloatingActionButton.small(
                          heroTag: null,
                          tooltip: l10n.chatJumpToLatest,
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
                key: const Key('chat-live-region'),
                liveRegion: true,
                label: _announcement,
                child: const SizedBox(width: double.infinity, height: 1),
              ),
              if (messages.isNotEmpty && !chat.isStreaming && !compact)
                ChatPromptStrip(onPrompt: _send),
              // The field and Send sit outside any scroll so they are never
              // clipped; with the keyboard open or large text it grows less.
              ChatInputBar(
                controller: _input,
                streaming: chat.isStreaming,
                maxLines: compact ? 3 : 5,
                onSend: _send,
                onStop: () => ref.read(chatProvider.notifier).stop(),
              ),
              // The empty view shows the disclaimer itself. Here it never
              // takes more than a quarter of the height; past that it
              // scrolls, so the conversation and the field keep their room.
              if (messages.isNotEmpty)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight / 4,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.xs,
                      AppSpacing.lg,
                      AppSpacing.sm,
                    ),
                    child: Text(
                      l10n.chatDisclaimer,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(height: AppSpacing.sm),
            ],
          );
        },
      ),
    );
  }
}
