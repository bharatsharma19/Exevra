import 'package:flutter/material.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/date_helpers.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/expense.dart';
import 'category_avatar.dart';

/// The newest expenses of the same scope as the summary card above it,
/// with loading, empty and error states.
class RecentExpensesSection extends StatelessWidget {
  const RecentExpensesSection({
    required this.title,
    required this.expenses,
    required this.loading,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.onSeeAll,
    required this.onRetry,
    required this.canEdit,
    required this.onOpen,
    this.error,
    this.onAdd,
    super.key,
  });

  final String title;
  final List<Expense> expenses;
  final bool loading;
  final Object? error;
  final String emptyTitle;
  final String emptyMessage;
  final VoidCallback onSeeAll;
  final VoidCallback onRetry;
  final bool Function(Expense expense) canEdit;
  final void Function(Expense expense) onOpen;

  /// Call to action of the empty state; null hides the button (for example
  /// while the first-expense tip already offers it, or for group viewers).
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final Widget body;
    if (expenses.isEmpty && error != null) {
      body = AppCard(
        child: ErrorState(
          message: friendlyMessage(
            error is AppFailure
                ? error! as AppFailure
                : const AppFailure.unknown(),
          ),
          onRetry: onRetry,
        ),
      );
    } else if (expenses.isEmpty && loading) {
      body = const AppCard(
        padding: EdgeInsets.zero,
        child: SkeletonList(itemCount: 3),
      );
    } else if (expenses.isEmpty) {
      body = AppCard(
        key: const Key('dashboard-empty'),
        child: EmptyState(
          icon: Icons.receipt_long_outlined,
          title: emptyTitle,
          message: emptyMessage,
          actionLabel: onAdd == null ? null : l10n.dashboardAddExpense,
          onAction: onAdd,
        ),
      );
    } else {
      body = AppCard(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          children: [
            for (var i = 0; i < expenses.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: AppSpacing.lg,
                  endIndent: AppSpacing.lg,
                  color: context.palette.outlineVariant,
                ),
              _ExpenseRow(
                expense: expenses[i],
                onTap: canEdit(expenses[i]) ? () => onOpen(expenses[i]) : null,
              ),
            ],
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: title,
          actionLabel: l10n.dashboardSeeAll,
          onAction: onSeeAll,
          padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.xs),
        ),
        body,
      ],
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({required this.expense, required this.onTap});

  final Expense expense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final when =
        '${DateHelpers.formatShortDate(expense.spentAt)}, '
        '${DateHelpers.formatTime(expense.spentAt)}';
    return AppListTile(
      leading: CategoryAvatar(category: expense.category),
      title: expense.title,
      subtitle: l10n.dashboardExpenseSubtitle(expense.category, when),
      onTap: onTap,
      trailing: AmountText(
        MoneyFormat.format(expense.amount),
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}
