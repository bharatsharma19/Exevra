import '../../core/errors/app_failure.dart';
import '../../core/errors/failure_messages.dart';
import '../../data/ai/ai_chat_models.dart';

/// User-facing text of the assistant feature.
abstract final class ChatCopy {
  static const String assistantName = 'Exevra Assistant';
  static const String disclaimer =
      'Exevra Assistant can make mistakes. Not financial advice.';
  static const String interrupted = 'Response interrupted. Tap Retry.';
  static const String stopped = 'Stopped.';
  static const String truncated =
      'This answer reached its length limit and may be incomplete.';
  static const String responding = 'Assistant is responding';
  static const String complete = 'Response complete';
  static const String declinedFallback =
      "I can't help with that. Try asking about your spending, budgets or "
      'ways to save.';

  static const String emptyTitle = 'Ask about your money';
  static const String emptyBody =
      'Ask about your spending, budgets or ways to save, or tap a prompt '
      'below to get started.';

  /// Longest server message shown as is.
  static const int maxServerMessageLength = 300;

  /// Codes whose server copy is shown in place of the local text: the
  /// server knows whether a limit is the user's or every provider's, and
  /// when the quota resets.
  static const Set<AiErrorCode> _serverWorded = {
    AiErrorCode.rateLimited,
    AiErrorCode.quotaExceeded,
    AiErrorCode.unavailable,
  };

  /// Friendly copy for [code]: the server's [serverMessage] (which the
  /// contract defines as friendly copy) for limits and outages, else local
  /// text. Never exception text.
  static String error(AiErrorCode? code, {String? serverMessage}) {
    final server = serverMessage?.trim() ?? '';
    if (code != null &&
        _serverWorded.contains(code) &&
        server.isNotEmpty &&
        server.length <= maxServerMessageLength) {
      return server;
    }
    return _local(code);
  }

  static String _local(AiErrorCode? code) => switch (code) {
    AiErrorCode.offline => friendlyMessage(const AppFailure.offline()),
    AiErrorCode.network =>
      "Couldn't reach the assistant. Check your connection and try again.",
    AiErrorCode.timeout =>
      'The assistant took too long to respond. Please try again.',
    AiErrorCode.unauthorized =>
      'Your session has expired. Please sign in again.',
    AiErrorCode.consentRequired =>
      'Allow the assistant to use your spending summary to continue.',
    AiErrorCode.rateLimited =>
      "You're sending messages quickly. Try again in a minute.",
    AiErrorCode.quotaExceeded =>
      "You've reached today's assistant limit. It resets at midnight UTC.",
    AiErrorCode.tooLong =>
      'That conversation is too long. Clear the chat and try again.',
    AiErrorCode.unavailable =>
      'The assistant is unavailable right now. Please try again shortly.',
    AiErrorCode.declined => declinedFallback,
    AiErrorCode.invalidRequest ||
    AiErrorCode.aborted ||
    AiErrorCode.unknown ||
    null => 'Something went wrong. Please try again.',
  };
}
