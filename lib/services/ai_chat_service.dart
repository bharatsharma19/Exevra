/// Client contract for the financial assistant.
///
/// The assistant runs server-side; the app holds no model provider keys.
/// Until the server endpoint ships, [UnavailableAiChatService] is the only
/// implementation and every request fails with [AiUnavailable].
library;

/// A reply from the assistant.
class AiChatReply {
  const AiChatReply({required this.text});

  final String text;
}

/// A typed failure the chat UI can show to the user as-is.
sealed class AiChatFailure implements Exception {
  const AiChatFailure();

  /// Friendly, non-technical copy for the user.
  String get userMessage;

  @override
  String toString() => userMessage;
}

/// The assistant is not available in this version of the app.
final class AiUnavailable extends AiChatFailure {
  const AiUnavailable();

  @override
  String get userMessage =>
      'The assistant is getting an upgrade. Please check back soon.';
}

/// Sends a question to the financial assistant.
abstract interface class AiChatService {
  /// Returns the assistant's reply or throws an [AiChatFailure].
  Future<AiChatReply> ask(String prompt);
}

/// Placeholder used until the server-side assistant is available.
///
/// Scope rules (finance-only questions) will be enforced by the server.
class UnavailableAiChatService implements AiChatService {
  const UnavailableAiChatService();

  @override
  Future<AiChatReply> ask(String prompt) async {
    throw const AiUnavailable();
  }
}
