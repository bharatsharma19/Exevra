import 'package:flutter/material.dart';

import '../../../core/accessibility/focus_outline.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/date_helpers.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/expense.dart';
import '../expense_categories.dart';

/// Actions in an expense row's menu.
enum ExpenseAction {
  /// Open the editor.
  edit,

  /// Delete (after confirming).
  delete,
}

/// One expense in the list: category icon, title, category and time, who
/// paid (group expenses) and the amount, plus an actions menu.
///
/// A locked group expense (someone in it left the group) shows a lock and
/// the reason, and its Delete item is disabled.
///
/// The row body is one screen reader item and one button (edit); the menu
/// is a separate button so it stays reachable.
class ExpenseTile extends StatelessWidget {
  /// Creates the row.
  const ExpenseTile({
    required this.expense,
    required this.payerLabel,
    required this.onTap,
    required this.canEdit,
    required this.canDelete,
    required this.onAction,
    this.locked = false,
    super.key,
  });

  /// The expense.
  final Expense expense;

  /// "Paid by …" for group expenses, "Personal" for personal ones in a
  /// mixed list, or null to show nothing.
  final String? payerLabel;

  /// Opens the expense.
  final VoidCallback onTap;

  /// Whether Edit is offered in the menu.
  final bool canEdit;

  /// Whether Delete is offered in the menu.
  final bool canDelete;

  /// Called with the chosen menu action.
  final ValueChanged<ExpenseAction> onAction;

  /// Whether the expense is locked because someone in it left the group:
  /// the row says so and Delete is disabled (the title, category, date and
  /// note stay editable).
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final category = categoryLabel(l10n, expense.category);
    final when =
        '${DateHelpers.formatShortDate(expense.spentAt)}, '
        '${DateHelpers.formatTime(expense.spentAt)}';
    final amount = AmountText(
      MoneyFormat.format(expense.amount),
      showSign: false,
      style: textTheme.titleMedium,
    );
    final categoryColor = palette.categoryColor(expense.category);

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          expense.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleSmall?.copyWith(color: palette.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          '$category · $when',
          style: textTheme.bodySmall?.copyWith(color: palette.textSecondary),
        ),
        if (payerLabel != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Row(
            children: [
              Icon(
                expense.isGroup
                    ? Icons.groups_rounded
                    : Icons.person_outline_rounded,
                size: 14,
                color: palette.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  payerLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (locked) ...[
          const SizedBox(height: AppSpacing.xxs),
          Row(
            key: const Key('expense-locked'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: palette.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  l10n.expensesLockedRow,
                  style: textTheme.labelMedium?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (stacked) ...[const SizedBox(height: AppSpacing.xs), amount],
      ],
    );

    final body = MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.lgAll,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: categoryColor.withValues(alpha: 0.14),
                    ),
                    child: SizedBox.square(
                      dimension: 40,
                      child: Icon(
                        AppConstants.getCategoryIcon(expense.category),
                        color: categoryColor,
                        size: 22,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: details),
                if (!stacked) ...[const SizedBox(width: AppSpacing.sm), amount],
              ],
            ),
          ),
        ),
      ),
    );

    return AppCard(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Expanded(
            child: FocusOutline(borderRadius: AppRadius.lgAll, child: body),
          ),
          if (canEdit || canDelete)
            PopupMenuButton<ExpenseAction>(
              tooltip: l10n.expensesActionsTooltip(expense.title),
              icon: Icon(Icons.more_vert_rounded, color: palette.textSecondary),
              onSelected: onAction,
              itemBuilder: (context) => [
                if (canEdit)
                  PopupMenuItem(
                    value: ExpenseAction.edit,
                    child: ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: Text(l10n.expensesEdit),
                    ),
                  ),
                if (canDelete && locked)
                  PopupMenuItem(
                    enabled: false,
                    value: ExpenseAction.delete,
                    child: ListTile(
                      enabled: false,
                      leading: const Icon(Icons.lock_outline_rounded),
                      title: Text(l10n.delete),
                      subtitle: Text(l10n.expensesLockedRow),
                    ),
                  )
                else if (canDelete)
                  PopupMenuItem(
                    value: ExpenseAction.delete,
                    child: ListTile(
                      leading: Icon(
                        Icons.delete_outline_rounded,
                        color: palette.danger,
                      ),
                      title: Text(
                        l10n.delete,
                        style: TextStyle(color: palette.danger),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
