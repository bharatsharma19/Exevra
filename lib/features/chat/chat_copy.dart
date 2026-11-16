/// Text the assistant feature once stored. Everything on screen comes from
/// the ARB (`chat*` keys) through `context.l10n`.
abstract final class ChatCopy {
  /// What older versions saved as the text of a declined answer without
  /// the server's own copy. Restored history drops it, so the bubble shows
  /// the localized `chatDeclinedFallback` instead.
  static const String legacyDeclinedText =
      "I can't help with that. Try asking about your spending, budgets or "
      'ways to save.';
}
