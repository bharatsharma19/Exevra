import 'package:flutter/material.dart';

import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';

/// Shown after "Not now": the assistant stays off until the user turns it
/// on (which shows the consent disclosure again).
class AssistantOffView extends StatelessWidget {
  const AssistantOffView({required this.onTurnOn, super.key});

  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return EmptyState(
      key: const Key('chat-assistant-off'),
      icon: Icons.chat_bubble_outline_rounded,
      title: l10n.chatOffTitle,
      message: l10n.chatOffBody,
      actionLabel: l10n.chatOffAction,
      onAction: onTurnOn,
    );
  }
}
