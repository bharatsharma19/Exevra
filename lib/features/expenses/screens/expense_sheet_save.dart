import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../l10n/l10n.dart';
import '../../../models/expense.dart';
import '../../../providers/expense_provider.dart';

/// What [saveExpense] did.
///
/// [failure] is null when everything was saved. [closed] is true when the
/// sheet must close even though [failure] is set: the expense was moved,
/// so the form no longer matches anything it could retry.
typedef ExpenseSaveOutcome = ({AppFailure? failure, bool closed});

/// Saves the expense sheet's [draft] through the list [key]: a new
/// expense, an edit in place, or a move to another scope (personal <->
/// group) with its edits.
///
/// After a move, a snack bar offers Undo. Undo restores the expense
/// exactly as it was before the sheet saved it: back to its old scope
/// *and* with its old title, amount, currency, category, date and note
/// (the move saved those edits too). Errors are not reported to the shell;
/// the sheet shows them.
Future<ExpenseSaveOutcome> saveExpense({
  required WidgetRef ref,
  required BuildContext context,
  required ExpenseListKey key,
  required Expense? existing,
  required ExpenseDraft draft,
  required String? groupName,
}) async {
  // Captured before the await: the sheet may be gone afterwards.
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final notifier = ref.read(expenseListProvider(key).notifier);

  if (existing == null) {
    return (failure: await notifier.add(draft, report: false), closed: false);
  }
  if (existing.groupId == draft.groupId) {
    final failure = await notifier.edit(
      existing.copyWith(
        title: draft.title.trim(),
        amount: draft.amount,
        category: draft.category,
        spentAt: draft.spentAt,
        note: draft.note,
      ),
      report: false,
    );
    return (failure: failure, closed: false);
  }

  final result = await notifier.move(existing, draft, report: false);
  final moved = result.moved;
  final failure = result.failure;
  if (moved == null) return (failure: failure, closed: false);
  if (failure != null) {
    // Moved, but the edits after the move were not saved: the moved row
    // still has the old fields, so Undo only needs to move it back.
    unawaited(
      _offerUndo(
        container,
        key,
        messenger,
        message: l10n.expensesMovedNotSaved(
          moved.title,
          friendlyMessage(failure),
        ),
        undo: (list) => list.moveTo(moved, groupId: existing.groupId),
        restored: l10n.expensesMoveUndone(existing.title),
      ),
    );
    return (failure: failure, closed: true);
  }
  unawaited(
    _offerUndo(
      container,
      key,
      messenger,
      message: moved.isGroup
          ? l10n.expensesMovedToGroup(moved.title, groupName ?? '')
          : l10n.expensesMovedToPersonal(moved.title),
      // Back to the old scope with the old fields, in the order the server
      // accepts (see ExpenseListNotifier.move).
      undo: (list) => list.move(moved, ExpenseDraft.fromExpense(existing)),
      restored: l10n.expensesMoveUndone(existing.title),
    ),
  );
  return (failure: null, closed: false);
}

/// Shows [message] with Undo; Undo runs [undo] on the list. The sheet is
/// gone by then, so the list is kept alive through [container] while it
/// runs. A failure is reported (and shown once by the shell).
Future<void> _offerUndo(
  ProviderContainer container,
  ExpenseListKey key,
  ScaffoldMessengerState? messenger, {
  required String message,
  required Future<MoveResult> Function(ExpenseListNotifier list) undo,
  required String restored,
}) async {
  final wantsUndo = await AppSnackbar.showUndo(message, messenger: messenger);
  if (!wantsUndo) return;
  final list = container.listen(expenseListProvider(key).notifier, (_, _) {});
  try {
    final result = await undo(list.read());
    if (result.failure == null) {
      AppSnackbar.showSuccess(restored, messenger: messenger);
    }
  } finally {
    list.close();
  }
}
