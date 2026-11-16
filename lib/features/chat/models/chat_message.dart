import '../../../data/ai/ai_chat_models.dart';
import '../chat_copy.dart';

/// Where an assistant answer stands.
enum ChatMessageStatus {
  /// A user message, or an answer that finished normally.
  done,

  /// Tokens are arriving.
  streaming,

  /// Complete, but the output cap was reached.
  truncated,

  /// The provider stopped part-way; the partial text is kept.
  interrupted,

  /// The user pressed Stop; the partial text is kept.
  stopped,

  /// The provider refused; [ChatMessage.text] is the server's friendly
  /// decline, or empty when it sent none (the bubble then shows the app's
  /// own localized copy).
  declined,

  /// No answer; [ChatMessage.errorCode] says why.
  error,
}

/// One bubble of the conversation.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.isUser,
    required this.text,
    required this.createdAt,
    this.status = ChatMessageStatus.done,
    this.provider,
    this.errorCode,
    this.serverMessage,
  });

  final String id;
  final bool isUser;
  final String text;
  final DateTime createdAt;
  final ChatMessageStatus status;

  /// The model that wrote an answer (label only).
  final AiProvider? provider;

  /// Set when [status] is [ChatMessageStatus.error].
  final AiErrorCode? errorCode;

  /// The server's friendly copy for [errorCode], when it sent one.
  final String? serverMessage;

  bool get isStreaming => status == ChatMessageStatus.streaming;

  /// Whether Retry is offered for this answer.
  bool get canRetry =>
      !isUser &&
      (status == ChatMessageStatus.error ||
          status == ChatMessageStatus.interrupted ||
          status == ChatMessageStatus.stopped);

  /// Whether the text may be copied, reported and sent back as history.
  bool get hasUsableText =>
      text.trim().isNotEmpty &&
      status != ChatMessageStatus.error &&
      status != ChatMessageStatus.streaming;

  ChatMessage copyWith({
    String? text,
    ChatMessageStatus? status,
    AiProvider? provider,
    bool clearProvider = false,
    AiErrorCode? errorCode,
    String? serverMessage,
    bool clearError = false,
  }) {
    return ChatMessage(
      id: id,
      isUser: isUser,
      text: text ?? this.text,
      createdAt: createdAt,
      status: status ?? this.status,
      provider: clearProvider ? null : provider ?? this.provider,
      errorCode: clearError ? null : errorCode ?? this.errorCode,
      serverMessage: clearError ? null : serverMessage ?? this.serverMessage,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'user': isUser,
    'text': text,
    'at': createdAt.toUtc().toIso8601String(),
    'status': status.name,
    'provider': ?provider?.name,
    'error': ?errorCode?.name,
    'notice': ?serverMessage,
  };

  /// Restores a saved message; null when [json] is not one. A message saved
  /// while streaming comes back as interrupted.
  static ChatMessage? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final isUser = json['user'];
    final text = json['text'];
    final at = DateTime.tryParse(
      json['at'] is String ? json['at'] as String : '',
    );
    if (id is! String || isUser is! bool || text is! String || at == null) {
      return null;
    }
    var status = ChatMessageStatus.values
        .where((s) => s.name == json['status'])
        .firstOrNull;
    status ??= ChatMessageStatus.done;
    if (status == ChatMessageStatus.streaming) {
      status = ChatMessageStatus.interrupted;
    }
    // Older saves stored the English fallback of a decline as its text.
    final legacyDecline =
        status == ChatMessageStatus.declined &&
        text == ChatCopy.legacyDeclinedText;
    return ChatMessage(
      id: id,
      isUser: isUser,
      text: legacyDecline ? '' : text,
      createdAt: at,
      status: isUser ? ChatMessageStatus.done : status,
      provider: AiProvider.values
          .where((p) => p.name == json['provider'])
          .firstOrNull,
      errorCode: AiErrorCode.values
          .where((c) => c.name == json['error'])
          .firstOrNull,
      serverMessage: json['notice'] is String ? json['notice'] as String : null,
    );
  }
}
