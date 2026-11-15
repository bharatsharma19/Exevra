import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';
import '../core/utils/haptics.dart';
import '../services/ai_chat_service.dart';
import 'auth_provider.dart';

class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final String? modelUsed;
  final bool isStreaming;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.modelUsed,
    this.isStreaming = false,
  });

  ChatMessage copyWith({
    String? id,
    String? text,
    bool? isUser,
    DateTime? timestamp,
    String? modelUsed,
    bool? isStreaming,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      modelUsed: modelUsed ?? this.modelUsed,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
}

class ChatState {
  final List<ChatMessage> messages;
  final bool isGenerating;
  final String? activeModel;
  final String? errorMessage;

  const ChatState({
    this.messages = const [],
    this.isGenerating = false,
    this.activeModel,
    this.errorMessage,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isGenerating,
    String? activeModel,
    Object? errorMessage = const Object(),
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isGenerating: isGenerating ?? this.isGenerating,
      activeModel: activeModel ?? this.activeModel,
      errorMessage: errorMessage == const Object()
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

/// The assistant conversation of the signed-in user. It lives in memory
/// only and starts over when the user changes, so no conversation is ever
/// shown to another account.
class ChatNotifier extends Notifier<ChatState> {
  AiChatService get _aiService => ref.read(aiChatServiceProvider);

  @override
  ChatState build() {
    ref.watch(currentUserIdProvider);
    ref.watch(aiChatServiceProvider);
    return ChatState(messages: [_welcome()]);
  }

  static const String assistantName = 'Exevra Assistant';
  static const String genericFailureMessage =
      'Something went wrong. Please try again.';

  static ChatMessage _welcome() {
    return ChatMessage(
      id: 'msg-welcome',
      text:
          '👋 **Welcome to the Exevra Assistant**\n\n'
          'Ask about your spending, budgets or ways to save. '
          'Tap a quick prompt below to get started.',
      isUser: false,
      timestamp: DateTime.now(),
      modelUsed: assistantName,
      isStreaming: false,
    );
  }

  Future<void> sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty || state.isGenerating) return;
    final owner = ref.read(currentUserIdProvider);

    AppHaptics.light();

    final userMsg = ChatMessage(
      id: 'msg-${DateTime.now().millisecondsSinceEpoch}',
      text: query,
      isUser: true,
      timestamp: DateTime.now(),
    );

    final assistantMsgId = 'msg-ai-${DateTime.now().millisecondsSinceEpoch}';
    final assistantMsg = ChatMessage(
      id: assistantMsgId,
      text: '',
      isUser: false,
      timestamp: DateTime.now(),
      isStreaming: true,
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg, assistantMsg],
      isGenerating: true,
      errorMessage: null,
    );

    String replyText;
    String? failureMessage;
    try {
      final reply = await _aiService.ask(query);
      replyText = reply.text;
      AppHaptics.medium();
    } on AiChatFailure catch (failure) {
      replyText = failure.userMessage;
      failureMessage = failure.userMessage;
    } catch (e, stackTrace) {
      AppLogger.error('Assistant request failed', e, stackTrace);
      AppHaptics.error();
      replyText = genericFailureMessage;
      failureMessage = genericFailureMessage;
    }

    // The user changed while waiting: this reply is not theirs.
    if (!ref.mounted || ref.read(currentUserIdProvider) != owner) return;
    state = state.copyWith(
      messages: state.messages.map((m) {
        if (m.id == assistantMsgId) {
          return m.copyWith(
            text: replyText,
            modelUsed: assistantName,
            isStreaming: false,
          );
        }
        return m;
      }).toList(),
      isGenerating: false,
      errorMessage: failureMessage,
    );
  }

  void clearChat() {
    AppHaptics.medium();
    state = ChatState(messages: [_welcome()]);
  }
}

final aiChatServiceProvider = Provider<AiChatService>(
  (ref) => const UnavailableAiChatService(),
);

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);
