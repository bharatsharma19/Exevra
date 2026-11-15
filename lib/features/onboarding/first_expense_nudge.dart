import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_icon_button.dart';
import '../../l10n/l10n.dart';
import 'onboarding_store.dart';

/// A tip card, "Add your first expense", with a call to action and a
/// dismiss button.
///
/// Show it where the expense list is empty (for example at the top of the
/// dashboard while the user has no expenses). Dismissing hides it for good on
/// this device through [firstExpenseNudgeDismissedProvider]. It renders
/// nothing while that flag loads, so it never flashes up for users who
/// already dismissed it.
class FirstExpenseNudge extends ConsumerWidget {
  /// Creates the tip.
  const FirstExpenseNudge({required this.onAddExpense, super.key});

  /// Opens the add-expense flow.
  final VoidCallback onAddExpense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(firstExpenseNudgeDismissedProvider).value;
    if (dismissed ?? true) return const SizedBox.shrink();

    final l10n = context.l10n;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.accentContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Icon(
                        Icons.receipt_long_outlined,
                        color: palette.onAccentContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            l10n.firstExpenseNudgeTitle,
                            style: textTheme.titleMedium?.copyWith(
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          l10n.firstExpenseNudgeMessage,
                          style: textTheme.bodyMedium?.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                AppIconButton(
                  icon: Icons.close,
                  tooltip: l10n.firstExpenseNudgeDismiss,
                  onPressed: () => unawaited(
                    ref
                        .read(firstExpenseNudgeDismissedProvider.notifier)
                        .dismiss(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpacing.md),
              child: FilledButton.icon(
                onPressed: onAddExpense,
                icon: const Icon(Icons.add),
                label: Text(l10n.firstExpenseNudgeAction),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
