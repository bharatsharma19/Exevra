import 'package:flutter/material.dart';

import '../chat_copy.dart';
import '../widgets/consent_view.dart';

/// The assistant's consent disclosure as a full screen, for turning the
/// assistant on outside the chat tab (Settings). Consent is saved only
/// when the user taps Allow.
class AiConsentScreen extends StatelessWidget {
  const AiConsentScreen({super.key});

  /// Shows the disclosure. Completes with true when the user allowed the
  /// assistant (saved on the server), false otherwise.
  static Future<bool> show(BuildContext context) async {
    final allowed = await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => const AiConsentScreen(),
      ),
    );
    return allowed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(ChatCopy.assistantName)),
      body: ChatConsentView(
        onNotNow: () => Navigator.of(context).pop(false),
        onAllowed: () => Navigator.of(context).pop(true),
      ),
    );
  }
}
