import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/failure_messages.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/money_format.dart';
import '../../core/widgets/widgets.dart';
import '../../l10n/l10n.dart';
import '../../models/expense.dart';
import '../../providers/auth_provider.dart';
import '../../providers/expense_provider.dart';

/// Whether [expense] is a group expense locked because someone who shares
/// it left the group (the server would refuse a delete or amount change).
/// False when the check fails: the server still decides.
Future<bool> isExpenseLockedNow(WidgetRef ref, Expense expense) async {
  final lockKey = expenseLockKeyOf(expense);
  if (lockKey == null) return false;
  final check = ref.listenManual(
    expenseLockedProvider(lockKey).future,
    (_, _) {},
  );
  try {
    return await check.read();
  } on Object {
    return false;
  } finally {
    check.close();
  }
}

/// Explains, with a lock icon, that [expense] cannot be changed.
Future<void> showExpenseLockedDialog(BuildContext context) {
  final l10n = context.l10n;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.lock_outline_rounded),
      scrollable: true,
      title: Text(l10n.expensesLockedTitle),
      content: Text(friendlyMessageForKey('expense_locked_member_left')),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.ok),
        ),
      ],
    ),
  );
}

/// Deletes [expense] from the list [key] after the user confirms, then
/// offers Undo.
///
/// A locked group expense is not deleted; the lock is explained instead.
/// Undo saves the expense again as the current user, so it is offered only
/// to the payer (an admin deleting someone else's expense is told it
/// cannot be undone before confirming). A failure is rolled back and shown
/// once by the shell.
Future<void> deleteExpenseWithUndo(
  BuildContext context,
  WidgetRef ref, {
  required Expense expense,
  required ExpenseListKey key,
}) async {
  AppHaptics.heavy();
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (await isExpenseLockedNow(ref, expense)) {
    if (context.mounted) await showExpenseLockedDialog(context);
    return;
  }
  if (!context.mounted) return;
  final userId = ref.read(currentUserIdProvider);
  final canUndo = expense.userId != null && expense.userId == userId;
  final amount = MoneyFormat.format(expense.amount);
  final confirmed = await showConfirmDialog(
    context,
    title: l10n.expensesDeleteTitle,
    message: [
      if (expense.isGroup)
        l10n.expensesDeleteGroupMessage(expense.title, amount)
      else
        l10n.expensesDeleteMessage(expense.title, amount),
      if (!canUndo) l10n.expensesDeleteNoUndo,
    ].join(' '),
    confirmLabel: l10n.delete,
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;

  final container = ProviderScope.containerOf(context, listen: false);
  final list = container.listen(expenseListProvider(key).notifier, (_, _) {});
  try {
    final failure = await list.read().remove(expense);
    if (failure != null) return;
    final deleted = l10n.expensesDeleted(expense.title);
    if (!canUndo) {
      AppSnackbar.showInfo(deleted, messenger: messenger);
      return;
    }
    final undo = await AppSnackbar.showUndo(deleted, messenger: messenger);
    if (!undo) return;
    final restore = await list.read().add(ExpenseDraft.fromExpense(expense));
    if (restore == null) {
      AppSnackbar.showSuccess(
        l10n.expensesRestored(expense.title),
        messenger: messenger,
      );
    }
  } finally {
    list.close();
  }
}
