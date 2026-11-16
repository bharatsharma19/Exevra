import 'package:intl/intl.dart';

import '../../core/errors/app_failure.dart';
import '../../core/errors/failure_messages.dart';
import '../../data/ai/ai_chat_models.dart';
import '../../l10n/l10n.dart';
import '../../core/utils/app_clock.dart';

/// Longest server message shown as is.
const int chatMaxServerMessageLength = 300;

/// Codes whose server copy is shown in place of the local text: the server
/// knows whether a limit is the user's (per-minute rate) or every
/// provider's. The daily limit always uses local text so its reset time is
/// in the device's time zone and format.
const Set<AiErrorCode> _serverWorded = {
  AiErrorCode.rateLimited,
  AiErrorCode.unavailable,
};

/// When the daily assistant limit resets after [now], in local time: the
/// server resets every quota at the next midnight UTC.
DateTime chatQuotaResetsAt(DateTime now) {
  final utc = now.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day + 1).toLocal();
}

/// Friendly copy for a failed answer with [code]: the server's
/// [serverMessage] (which the contract defines as friendly copy) for limits
/// and outages, else local text. Never exception text. [now] (default: the
/// current time) sets the daily limit's reset time.
///
/// The daily limit ("You've reached today's assistant limit…") and the
/// per-minute limit ("You're sending messages quickly…") always read
/// differently.
String chatErrorText(
  AppLocalizations l10n,
  AiErrorCode? code, {
  String? serverMessage,
  DateTime? now,
}) {
  final server = serverMessage?.trim() ?? '';
  if (code != null &&
      _serverWorded.contains(code) &&
      server.isNotEmpty &&
      server.length <= chatMaxServerMessageLength) {
    return server;
  }
  return switch (code) {
    AiErrorCode.offline => friendlyMessage(const AppFailure.offline()),
    AiErrorCode.network => l10n.chatErrorNetwork,
    AiErrorCode.timeout => l10n.chatErrorTimeout,
    AiErrorCode.unauthorized => l10n.chatErrorUnauthorized,
    AiErrorCode.consentRequired => l10n.chatErrorConsent,
    AiErrorCode.rateLimited => l10n.chatErrorRateLimited,
    AiErrorCode.quotaExceeded => l10n.chatErrorQuota(
      DateFormat.jm().format(chatQuotaResetsAt(now ?? AppClock.now())),
    ),
    AiErrorCode.tooLong => l10n.chatErrorTooLong,
    AiErrorCode.unavailable => l10n.chatErrorUnavailable,
    AiErrorCode.declined => l10n.chatDeclinedFallback,
    AiErrorCode.invalidRequest ||
    AiErrorCode.aborted ||
    AiErrorCode.unknown ||
    null => l10n.chatErrorGeneric,
  };
}
