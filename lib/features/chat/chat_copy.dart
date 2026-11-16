/// Text the assistant feature stores, not shows. Everything on screen comes
/// from the ARB (`chat*` keys) through `context.l10n`.
abstract final class ChatCopy {
  /// Saved as the text of a declined answer when the server sent no copy
  /// of its own. The bubble shows `chatDeclinedFallback` in its place.
  static const String declinedFallback =
      "I can't help with that. Try asking about your spending, budgets or "
      'ways to save.';
}
