import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_constants.dart';
import '../services/ai_chatbot_service.dart';
import '../core/utils/haptics.dart';
import 'auth_provider.dart';
import 'expense_provider.dart';

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
      errorMessage: errorMessage == const Object() ? this.errorMessage : errorMessage as String?,
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  final AiChatbotService _aiService;
  final Ref _ref;

  ChatNotifier(this._aiService, this._ref) : super(const ChatState()) {
    _initWelcomeMessage();
  }

  void _initWelcomeMessage() {
    final welcome = ChatMessage(
      id: 'msg-welcome',
      text: '👋 **Welcome to Antigravity AI Advisor**\n\n'
          'I am your low-latency, privacy-first financial intelligence co-pilot. '
          'I can analyze your category expenditures, suggest budget limits, simulate scenarios, and uncover spending leaks.\n\n'
          'Tap any quick prompt below or ask me anything regarding your finances!',
      isUser: false,
      timestamp: DateTime.now(),
      modelUsed: 'Antigravity Intelligence Core',
      isStreaming: false,
    );
    state = state.copyWith(messages: [welcome]);
  }

  Future<void> sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty || state.isGenerating) return;

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

    try {
      final auth = _ref.read(authNotifierProvider);
      final expenseState = _ref.read(expenseProvider);
      final aiConsent = auth.profile?.aiConsent ?? false;
      final currency = auth.profile?.currency ?? AppConstants.defaultCurrency;

      final stream = _aiService.generateResponseStream(
        userPrompt: query,
        aiConsent: aiConsent,
        expenses: expenseState.expenses,
        currencyCode: currency,
      );

      String accumulated = '';
      String? modelUsed;

      await for (final chunk in stream) {
        accumulated += chunk.text;
        if (chunk.modelUsed != null) {
          modelUsed = chunk.modelUsed;
        }

        final updatedList = state.messages.map((m) {
          if (m.id == assistantMsgId) {
            return m.copyWith(
              text: accumulated,
              modelUsed: modelUsed,
              isStreaming: !chunk.isComplete,
            );
          }
          return m;
        }).toList();

        state = state.copyWith(
          messages: updatedList,
          activeModel: modelUsed,
          isGenerating: !chunk.isComplete,
        );
      }

      AppHaptics.medium();
    } catch (e) {
      AppHaptics.error();
      final updatedList = state.messages.map((m) {
        if (m.id == assistantMsgId) {
          return m.copyWith(
            text: '⚠️ An error occurred while contacting AI services: ${e.toString()}',
            isStreaming: false,
          );
        }
        return m;
      }).toList();
      state = state.copyWith(
        messages: updatedList,
        isGenerating: false,
        errorMessage: e.toString(),
      );
    }
  }

  void clearChat() {
    AppHaptics.medium();
    _initWelcomeMessage();
  }
}

final aiChatbotServiceProvider = Provider<AiChatbotService>((ref) => AiChatbotService.instance);

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final aiService = ref.watch(aiChatbotServiceProvider);
  return ChatNotifier(aiService, ref);
});
