/// Wire types of the `ai-chat` Edge Function (see
/// `supabase/functions/README.md`, "ai-chat contract").
library;

import 'dart:convert';

/// Who wrote a turn.
enum AiRole { user, assistant }

/// One conversation turn sent to the server.
class AiTurn {
  const AiTurn(this.role, this.content);

  const AiTurn.user(String content) : this(AiRole.user, content);
  const AiTurn.assistant(String content) : this(AiRole.assistant, content);

  final AiRole role;
  final String content;

  Map<String, Object> toJson() => {'role': role.name, 'content': content};

  @override
  bool operator ==(Object other) =>
      other is AiTurn && other.role == role && other.content == content;

  @override
  int get hashCode => Object.hash(role, content);

  @override
  String toString() => 'AiTurn(${role.name}, ${content.length} chars)';
}

/// The request body of `POST /functions/v1/ai-chat`.
class AiChatRequest {
  const AiChatRequest({
    required this.messages,
    required this.timeZone,
    this.locale,
    this.days = defaultDays,
  });

  /// Server limits, counted in UTF-16 code units (Dart `String.length`).
  static const int maxTurns = 20;
  static const int maxUserMessageLength = 2000;
  static const int maxMessageLength = 4000;
  static const int maxTotalLength = 24000;
  static const int defaultDays = 90;

  final List<AiTurn> messages;
  final String timeZone;
  final String? locale;
  final int days;

  String encode() => jsonEncode({
    'messages': [for (final m in messages) m.toJson()],
    'tz': timeZone,
    'locale': ?locale,
    'days': days,
  });
}

/// The model that wrote an answer. Only these two labels are ever shown;
/// model ids never reach the UI.
enum AiProvider {
  claude('Claude'),
  gemini('Gemini');

  const AiProvider(this.label);

  /// Name shown to the user.
  final String label;

  /// The provider for a `meta.provider` value, null when unknown.
  static AiProvider? fromWire(Object? value) => switch (value) {
    'claude' => AiProvider.claude,
    'gemini' => AiProvider.gemini,
    _ => null,
  };
}

/// Why the assistant gave no (complete) answer.
enum AiErrorCode {
  /// The device has no connection.
  offline,

  /// The server could not be reached or the connection broke.
  network,

  /// No response (or no event) in time.
  timeout,

  /// The session could not be refreshed.
  unauthorized,

  /// `profiles.ai_consent` is not true on the server.
  consentRequired,

  /// Per-minute limit.
  rateLimited,

  /// Daily limit.
  quotaExceeded,

  /// The message or history is over the server's limits.
  tooLong,

  /// The server rejected the request body.
  invalidRequest,

  /// No provider could answer.
  unavailable,

  /// The provider refused to answer.
  declined,

  /// The request was cancelled by the app (Stop, Clear, sign-out).
  aborted,

  /// Anything else.
  unknown;

  /// The code for a server `error.code` value.
  static AiErrorCode? fromWire(Object? code) => switch (code) {
    'invalid_request' => AiErrorCode.invalidRequest,
    'unauthorized' => AiErrorCode.unauthorized,
    'consent_required' => AiErrorCode.consentRequired,
    'too_long' => AiErrorCode.tooLong,
    'quota_exceeded' => AiErrorCode.quotaExceeded,
    'rate_limited' => AiErrorCode.rateLimited,
    'unavailable' || 'internal' => AiErrorCode.unavailable,
    'declined' => AiErrorCode.declined,
    'offline' => AiErrorCode.offline,
    _ => null,
  };
}

/// A failure before or instead of an answer.
class AiChatException implements Exception {
  const AiChatException(this.code, {this.serverMessage, this.retryAfter});

  final AiErrorCode code;

  /// Friendly copy from the server, when it sent one.
  final String? serverMessage;

  /// From the `retry-after` header of a 429.
  final Duration? retryAfter;

  @override
  String toString() => 'AiChatException(${code.name})';
}

/// One event of an answer stream.
sealed class AiStreamEvent {
  const AiStreamEvent();
}

/// The answer comes from [provider] (null when the server named another).
final class AiMeta extends AiStreamEvent {
  const AiMeta(this.provider);
  final AiProvider? provider;
}

/// More answer text.
final class AiDelta extends AiStreamEvent {
  const AiDelta(this.text);
  final String text;
}

/// The answer is complete; [truncated] when the output cap was reached.
final class AiDone extends AiStreamEvent {
  const AiDone({this.truncated = false});
  final bool truncated;
}

/// The answer stopped part-way; keep the text and offer Retry.
final class AiInterrupted extends AiStreamEvent {
  const AiInterrupted({this.reason, this.message});
  final String? reason;
  final String? message;
}

/// No answer. With [discardPartial] the text shown so far must be replaced
/// by [message].
final class AiStreamError extends AiStreamEvent {
  const AiStreamError(this.code, {this.message, this.discardPartial = false});
  final AiErrorCode code;
  final String? message;
  final bool discardPartial;
}
