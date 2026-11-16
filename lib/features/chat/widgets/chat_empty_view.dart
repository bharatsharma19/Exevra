import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';

/// Suggested questions, in the order they are offered.
List<String> chatPrompts(AppLocalizations l10n) => [
  l10n.chatPromptTopCategories,
  l10n.chatPromptCompareWeek,
  l10n.chatPromptTips,
  l10n.chatPromptBudgetRule,
  l10n.chatPromptGroupFood,
];

/// The start of a conversation: what the assistant is for, suggested
/// questions and the disclaimer.
class ChatEmptyView extends StatelessWidget {
  const ChatEmptyView({required this.onPrompt, super.key});

  final void Function(String prompt) onPrompt;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.auto_awesome_outlined,
              size: 40,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Semantics(
            header: true,
            child: Text(
              l10n.chatEmptyTitle,
              style: theme.textTheme.titleLarge?.copyWith(
                color: scheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.chatEmptyBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl - 4),
          Semantics(
            container: true,
            label: l10n.chatPromptsLabel,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final prompt in chatPrompts(l10n))
                  ActionChip(
                    label: Text(prompt),
                    onPressed: () => onPrompt(prompt),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl - 4),
          Text(
            l10n.chatDisclaimer,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The suggested questions as one scrolling row above the input, once a
/// conversation has started.
class ChatPromptStrip extends StatelessWidget {
  const ChatPromptStrip({required this.onPrompt, super.key});

  final void Function(String prompt) onPrompt;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final prompts = chatPrompts(l10n);
    return Semantics(
      container: true,
      label: l10n.chatPromptsLabel,
      child: SizedBox(
        height: AppSizes.minTapTarget,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          itemCount: prompts.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (context, i) => Center(
            child: ActionChip(
              label: Text(prompts[i]),
              onPressed: () => onPrompt(prompts[i]),
            ),
          ),
        ),
      ),
    );
  }
}
