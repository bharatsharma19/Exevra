import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/utils/money_parser.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/expense.dart';
import '../../../models/group.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/expense_provider.dart';
import '../../../providers/groups_provider.dart';
import '../../../providers/profile_provider.dart';
import '../widgets/expense_amount_row.dart';
import '../widgets/expense_form_fields.dart';
import '../widgets/inline_notice.dart';
import '../widgets/money_input_field.dart';
import 'expense_sheet_save.dart';
import '../../../core/utils/app_clock.dart';

/// Adds a new expense or edits one.
///
/// * The amount is parsed with [MoneyParser] in the expense's currency and
///   the device locale: a group expense always uses the group currency; a
///   personal one any supported currency (the profile currency by default).
/// * An expense can be moved between personal and the active group by its
///   payer. A snack bar then offers Undo, which restores the expense
///   exactly as it was: its scope and every field changed with the move
///   (see [saveExpense]).
/// * A group expense shared with someone who left the group is locked: its
///   amount and group cannot change (title, category, date and note can),
///   which the sheet shows with a lock notice.
/// * Errors are shown inside the sheet; nothing is reported under the
///   modal barrier. Leaving with unsaved changes asks first.
class AddEditExpenseSheet extends ConsumerStatefulWidget {
  const AddEditExpenseSheet({super.key, this.existingExpense, this.listKey});

  final Expense? existingExpense;

  /// The list the sheet writes through (so its rows update at once).
  /// Defaults to the active scope's list.
  final ExpenseListKey? listKey;

  /// Opens the sheet. Completes with true when the server saved it.
  static Future<bool> show(
    BuildContext context, {
    Expense? expense,
    ExpenseListKey? listKey,
  }) async {
    final saved = await showAppSheet<bool>(
      context: context,
      // Dragging would close the sheet without the unsaved-changes check.
      guarded: true,
      showDragHandle: false,
      builder: (context) =>
          AddEditExpenseSheet(existingExpense: expense, listKey: listKey),
    );
    return saved ?? false;
  }

  @override
  ConsumerState<AddEditExpenseSheet> createState() =>
      _AddEditExpenseSheetState();
}

/// The values a form started with, to detect unsaved changes.
typedef _Snapshot = ({
  String title,
  String amount,
  String note,
  String category,
  DateTime spentAt,
  bool isGroup,
  String personalCurrency,
});

class _AddEditExpenseSheetState extends ConsumerState<AddEditExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late _Snapshot _initial;

  /// Whether the user picked Personal or Group themselves.
  bool _scopeChosen = false;

  late String _category;

  /// Local wall-clock time; sent as UTC.
  late DateTime _spentAt;
  late bool _isGroup;
  late String _personalCurrency;

  bool _isSubmitting = false;
  bool _allowPop = false;

  /// Server or pre-check failure, shown above the save button.
  String? _formError;

  /// Why the other scope is unavailable, after the user tapped it.
  String? _scopeHint;

  /// The server refused a change because the expense is locked (someone
  /// who shares it left the group), even if the check on opening missed it.
  bool _lockedByServer = false;

  /// Whether the edited expense is locked (see [expenseLockedProvider]);
  /// updated on every build.
  bool _locked = false;

  Expense? get _existing => widget.existingExpense;
  bool get _isEditing => _existing != null;

  @override
  void initState() {
    super.initState();
    final expense = _existing;
    _titleController = TextEditingController(text: expense?.title ?? '');
    _amountController = TextEditingController(
      text: expense != null ? MoneyFormat.forInput(expense.amount) : '',
    );
    _noteController = TextEditingController(text: expense?.note ?? '');
    _category = expense?.category ?? AppConstants.categories.first.name;
    final now = AppClock.now();
    _spentAt =
        expense?.spentAt.toLocal() ??
        DateTime(now.year, now.month, now.day, now.hour, now.minute);
    _isGroup = expense != null
        ? expense.isGroup
        : (ref.read(activeGroupProvider)?.canAddExpenses ?? false);
    _personalCurrency =
        expense?.amount.currency ?? ref.read(preferredCurrencyProvider);
    _initial = _snapshot();
    for (final c in [_titleController, _amountController, _noteController]) {
      c.addListener(_onTextChanged);
    }
    if (expense == null) {
      // Groups may still be loading when the sheet opens: default to the
      // active group once it is known, unless the user already chose.
      ref.listenManual(activeGroupProvider, (previous, next) {
        if (_scopeChosen || !mounted) return;
        final isGroup = next?.canAddExpenses ?? false;
        if (isGroup == _isGroup) return;
        final wasDirty = _isDirty;
        setState(() => _isGroup = isGroup);
        if (!wasDirty) _initial = _snapshot();
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // Rebuild so the unsaved-changes check sees the new text.
  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  _Snapshot _snapshot() => (
    title: _titleController.text.trim(),
    amount: _amountController.text.trim(),
    note: _noteController.text.trim(),
    category: _category,
    spentAt: _spentAt,
    isGroup: _isGroup,
    personalCurrency: _personalCurrency,
  );

  bool get _isDirty => _snapshot() != _initial;

  /// The group a group expense belongs to: its own group when editing one,
  /// otherwise the active group.
  Group? _targetGroup({bool listen = true}) {
    final existingGroupId = _existing?.groupId;
    if (existingGroupId == null) {
      return listen
          ? ref.watch(activeGroupProvider)
          : ref.read(activeGroupProvider);
    }
    final state = listen
        ? ref.watch(currentGroupsProvider)
        : ref.read(currentGroupsProvider);
    for (final g in state?.groups ?? const <Group>[]) {
      if (g.id == existingGroupId) return g;
    }
    return null;
  }

  /// Why the user cannot switch scope, or null when they can.
  String? _scopeUnavailableReason(Group? group, String? userId) {
    final existing = _existing;
    if (existing != null && existing.userId != userId) {
      return friendlyMessageForKey('not_expense_payer');
    }
    if (existing != null && existing.isGroup && _locked) {
      return friendlyMessageForKey('expense_locked_member_left');
    }
    if (group == null) return context.l10n.expensesNoGroupHint;
    if (!group.canAddExpenses) {
      return friendlyMessageForKey('viewer_cannot_add');
    }
    return null;
  }

  String _currency(Group? group) =>
      _isGroup && group != null ? group.currency : _personalCurrency;

  void _chooseScope(bool group, String? reason) {
    if (group == _isGroup) return;
    // Group needs a group the user can add to; leaving a group (when
    // editing) needs the payer and an unlocked expense.
    if (reason != null && (group || _isEditing)) {
      AppHaptics.error();
      setState(() => _scopeHint = reason);
      return;
    }
    AppHaptics.selection();
    setState(() {
      _isGroup = group;
      _scopeChosen = true;
      _scopeHint = null;
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() => _formError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final group = _targetGroup(listen: false);
    final userId = ref.read(currentUserIdProvider);
    final parsed = MoneyInputField.parse(
      _amountController.text,
      currency: _currency(group),
    );
    if (parsed is! MoneyParsed) return;
    final key = widget.listKey ?? ref.read(scopeExpenseKeyProvider);
    if (key == null || userId == null) {
      setState(() => _formError = friendlyMessageForKey('group_not_ready'));
      return;
    }
    if (_isGroup && !(group?.canAddExpenses ?? false)) {
      AppHaptics.error();
      setState(
        () => _formError =
            _scopeUnavailableReason(group, userId) ??
            friendlyMessageForKey('viewer_cannot_add'),
      );
      return;
    }

    final existing = _existing;
    final draft = ExpenseDraft(
      title: _titleController.text,
      // A locked expense keeps its amount (the field is read-only).
      amount: _locked && existing != null ? existing.amount : parsed.value,
      category: _category,
      spentAt: _spentAt.toUtc(),
      groupId: _isGroup ? group?.id : null,
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
    );

    setState(() => _isSubmitting = true);
    AppHaptics.light();
    final outcome = await saveExpense(
      ref: ref,
      context: context,
      key: key,
      existing: existing,
      draft: draft,
      groupName: group?.name,
    );
    if (!mounted) return;
    final failure = outcome.failure;
    if (failure != null && !outcome.closed) {
      final locked = failure.key == 'expense_locked_member_left';
      setState(() {
        _isSubmitting = false;
        _formError = friendlyMessage(failure);
        if (locked && existing != null) {
          // Keep only the changes the server still accepts.
          _lockedByServer = true;
          _isGroup = existing.isGroup;
          _amountController.text = MoneyFormat.forInput(existing.amount);
        }
      });
      return;
    }
    _close(true);
  }

  /// Pops the sheet once (never the page under it).
  void _close(bool saved) {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    _allowPop = true;
    Navigator.of(context).pop(saved);
  }

  Future<void> _confirmDiscard() async {
    final l10n = context.l10n;
    final discard = await showConfirmDialog(
      context,
      title: l10n.discardChangesTitle,
      message: _isEditing
          ? l10n.expensesDiscardEditMessage
          : l10n.expensesDiscardNewMessage,
      confirmLabel: l10n.discardChangesConfirm,
      cancelLabel: l10n.keepEditing,
      destructive: true,
    );
    if (discard) _close(false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final userId = ref.watch(currentUserIdProvider);
    final existing = _existing;
    final lockKey = existing == null ? null : expenseLockKeyOf(existing);
    _locked =
        _lockedByServer ||
        (lockKey != null &&
            (ref.watch(expenseLockedProvider(lockKey)).value ?? false));
    final group = _targetGroup();
    // Keeps the list this sheet writes to alive while it is open.
    final listKey = widget.listKey ?? ref.watch(scopeExpenseKeyProvider);
    if (listKey != null) ref.watch(expenseListProvider(listKey));
    final currency = _currency(group);
    final reason = _scopeUnavailableReason(group, userId);
    final currencyChanged =
        existing != null &&
        existing.amount.currency != currency &&
        _amountController.text.trim().isNotEmpty;
    final scopeHint =
        _scopeHint ?? (reason != null && _isGroup && !_locked ? reason : null);

    // Every dismissal (back, barrier, Close) comes here first, so the
    // check always sees the latest text. While saving, nothing closes the
    // sheet; the save closes it.
    return PopScope<Object?>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _isSubmitting) return;
        if (!_isDirty) {
          _close(false);
          return;
        }
        unawaited(_confirmDiscard());
      },
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ExpenseSheetHeader(
              title: _isEditing
                  ? l10n.expensesEditTitle
                  : l10n.expensesAddTitle,
            ),
            const SizedBox(height: AppSpacing.md),
            ExpenseAmountRow(
              controller: _amountController,
              currency: currency,
              currencyFixed: _isGroup && group != null,
              enabled: !_locked,
              lockedMessage: _locked
                  ? '${friendlyMessageForKey('expense_locked_member_left')} '
                        '${l10n.expensesLockedStillEditable}'
                  : null,
              warning: currencyChanged
                  ? l10n.expensesCurrencyChanged(currency)
                  : null,
              onCurrencyChanged: (value) {
                AppHaptics.selection();
                setState(() => _personalCurrency = value);
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            ExpenseTitleField(controller: _titleController),
            const SizedBox(height: AppSpacing.lg),
            ExpenseScopeSelector(
              isGroup: _isGroup,
              personalLocked: _isEditing && _isGroup && reason != null,
              groupLocked: !_isGroup && reason != null,
              onSelected: (group) => _chooseScope(group, reason),
              hint: scopeHint,
              caption: _isGroup && group != null
                  ? l10n.expensesGroupScopeCaption(group.name, group.currency)
                  : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            ExpenseCategoryPicker(
              selected: _category,
              onSelected: (name) {
                AppHaptics.selection();
                setState(() => _category = name);
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            ExpenseDateTimeFields(
              value: _spentAt,
              onChanged: (value) => setState(() => _spentAt = value),
            ),
            const SizedBox(height: AppSpacing.lg),
            ExpenseNoteField(controller: _noteController),
            if (_formError != null) ...[
              const SizedBox(height: AppSpacing.md),
              InlineNotice(
                key: const Key('expense-form-error'),
                kind: NoticeKind.error,
                message: _formError!,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            LoadingButton(
              key: const Key('expense-save'),
              label: _isEditing ? l10n.expensesSaveChanges : l10n.expensesSave,
              isLoading: _isSubmitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
