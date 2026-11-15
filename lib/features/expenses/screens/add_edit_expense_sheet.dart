import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/utils/date_helpers.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/utils/money_parser.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../models/currency_info.dart';
import '../../../models/expense.dart';
import '../../../models/group.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/expense_provider.dart';
import '../../../providers/groups_provider.dart';
import '../../../providers/profile_provider.dart';

/// Adds a new expense or edits one.
///
/// * The amount is parsed with [MoneyParser] in the expense's currency:
///   a group expense always uses the group currency; a personal one any
///   supported currency (the profile currency by default).
/// * An expense can be moved between personal and the active group by its
///   payer, in one server call (`move_expense_scope`, which gives it a new
///   id); a snack bar then offers Undo, which moves it back the same way.
/// * A group expense shared with someone who left the group is locked: its
///   amount and group cannot change (title, category, date and note can).
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
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Dragging would close the sheet without the unsaved-changes check.
      enableDrag: false,
      backgroundColor: Theme.of(
        context,
      ).colorScheme.surface.withValues(alpha: 0),
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
class _Snapshot {
  const _Snapshot({
    required this.title,
    required this.amount,
    required this.note,
    required this.category,
    required this.spentAt,
    required this.isGroup,
    required this.personalCurrency,
  });

  final String title;
  final String amount;
  final String note;
  final String category;
  final DateTime spentAt;
  final bool isGroup;
  final String personalCurrency;

  @override
  bool operator ==(Object other) =>
      other is _Snapshot &&
      other.title.trim() == title.trim() &&
      other.amount.trim() == amount.trim() &&
      other.note.trim() == note.trim() &&
      other.category == category &&
      other.spentAt == spentAt &&
      other.isGroup == isGroup &&
      other.personalCurrency == personalCurrency;

  @override
  int get hashCode => Object.hash(
    title.trim(),
    amount.trim(),
    note.trim(),
    category,
    spentAt,
    isGroup,
    personalCurrency,
  );
}

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

  /// Why the Group option is unavailable, after the user tapped it.
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
    final now = DateTime.now();
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

  void _onTextChanged() {
    // Rebuild so the unsaved-changes guard sees the new text.
    if (mounted) setState(() {});
  }

  _Snapshot _snapshot() => _Snapshot(
    title: _titleController.text,
    amount: _amountController.text,
    note: _noteController.text,
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
    final groups =
        (listen
                ? ref.watch(currentGroupsProvider)
                : ref.read(currentGroupsProvider))
            ?.groups ??
        const <Group>[];
    for (final g in groups) {
      if (g.id == existingGroupId) return g;
    }
    return null;
  }

  /// Why the user cannot choose Group, or null when they can.
  String? _groupUnavailableReason(Group? group, String? userId) {
    final existing = _existing;
    if (existing != null && existing.userId != userId) {
      return 'Only the person who paid can move this expense.';
    }
    if (existing != null && existing.isGroup && _locked) {
      return friendlyMessageForKey('expense_locked_member_left');
    }
    if (group == null) {
      return 'Create or join a group in Profile to add group expenses.';
    }
    if (!group.canAddExpenses) {
      return friendlyMessageForKey('viewer_cannot_add');
    }
    return null;
  }

  /// Whether the user can switch between Personal and Group.
  bool _canSwitchScope(Group? group, String? userId) =>
      _groupUnavailableReason(group, userId) == null;

  String _currency(Group? group) =>
      _isGroup && group != null ? group.currency : _personalCurrency;

  Future<void> _pickDate() async {
    AppHaptics.selection();
    final now = DateTime.now();
    final first = DateTime(2000);
    final last = DateTime(now.year + 1, now.month, now.day);
    var initial = DateTime(_spentAt.year, _spentAt.month, _spentAt.day);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _spentAt = DateHelpers.combineLocal(
        picked,
        _spentAt.hour,
        _spentAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    AppHaptics.selection();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_spentAt),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _spentAt = DateHelpers.combineLocal(_spentAt, picked.hour, picked.minute);
    });
  }

  void _chooseScope({required bool group, required String? reason}) {
    if (group == _isGroup) return;
    if (group && reason != null) {
      AppHaptics.error();
      setState(() => _scopeHint = reason);
      return;
    }
    if (!group && _isEditing && reason != null) {
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

  String? get _note {
    final text = _noteController.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() => _formError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final group = _targetGroup(listen: false);
    final userId = ref.read(currentUserIdProvider);
    final currency = _currency(group);
    final parsed = MoneyParser.parse(
      _amountController.text,
      currency: currency,
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
            _groupUnavailableReason(group, userId) ??
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
      note: _note,
    );

    setState(() => _isSubmitting = true);
    AppHaptics.light();
    final notifier = ref.read(expenseListProvider(key).notifier);
    final AppFailure? failure;
    Expense? moved;
    if (existing == null) {
      failure = await notifier.add(draft, report: false);
    } else if (existing.groupId != draft.groupId) {
      final result = await notifier.move(existing, draft, report: false);
      failure = result.failure;
      moved = result.moved;
    } else {
      failure = await notifier.edit(
        existing.copyWith(
          title: draft.title.trim(),
          amount: draft.amount,
          category: draft.category,
          spentAt: draft.spentAt,
          note: draft.note,
        ),
        report: false,
      );
    }

    if (!mounted) return;
    if (failure != null && moved != null) {
      // The move went through but the changes after it did not: the old
      // expense is gone, so this sheet cannot retry them.
      AppSnackbar.showError(
        'Moved "${moved.title}", but your other changes were not saved. '
        '${friendlyMessage(failure)}',
      );
      _allowPop = true;
      Navigator.of(context).pop(true);
      return;
    }
    if (failure != null) {
      final locked = failure.key == 'expense_locked_member_left';
      setState(() {
        _isSubmitting = false;
        _formError = friendlyMessage(failure!);
        if (locked && existing != null) {
          // Keep only the changes the server still accepts.
          _lockedByServer = true;
          _isGroup = existing.isGroup;
          _amountController.text = MoneyFormat.forInput(existing.amount);
        }
      });
      return;
    }
    if (existing != null && moved != null) {
      unawaited(
        _offerUndoMove(
          ProviderScope.containerOf(context, listen: false),
          key,
          moved,
          backTo: existing.groupId,
          message: moved.isGroup
              ? 'Moved "${moved.title}" to ${group?.name ?? 'the group'}.'
              : 'Moved "${moved.title}" to your personal expenses.',
        ),
      );
    }
    _allowPop = true;
    Navigator.of(context).pop(true);
  }

  /// Shows [message] with Undo; Undo moves [moved] back to [backTo] with
  /// the same single server call. The sheet is gone by then, so the list is
  /// kept alive through [container] while the move runs; a failure is
  /// reported (and shown once by the shell).
  static Future<void> _offerUndoMove(
    ProviderContainer container,
    ExpenseListKey key,
    Expense moved, {
    required String? backTo,
    required String message,
  }) async {
    final undo = await AppSnackbar.showUndo(message);
    if (!undo) return;
    final list = container.listen(expenseListProvider(key).notifier, (_, _) {});
    try {
      await list.read().moveTo(moved, groupId: backTo);
    } finally {
      list.close();
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: Text(
          _isEditing
              ? 'Your changes to this expense will be lost.'
              : 'This expense has not been saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      _allowPop = true;
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
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
    final reason = _groupUnavailableReason(group, userId);
    final canSwitch = _canSwitchScope(group, userId);
    final currencyChanged =
        _isEditing &&
        _existing!.amount.currency != currency &&
        _amountController.text.trim().isNotEmpty;

    return PopScope(
      // Every dismissal (back, barrier, Close) comes here first, so the
      // check always sees the latest text.
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _isSubmitting) return;
        if (!_isDirty) {
          _allowPop = true;
          Navigator.of(context).pop(false);
          return;
        }
        unawaited(_confirmDiscard());
      },
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              width: 1.5,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _header(scheme),
                  const SizedBox(height: 16),
                  _amountCard(scheme, isDark, currency, group),
                  if (_locked) ...[
                    const SizedBox(height: 10),
                    KeyedSubtree(
                      key: const Key('expense-locked'),
                      child: _hint(
                        scheme,
                        '${friendlyMessageForKey('expense_locked_member_left')} '
                        'You can still change the title, category, date and '
                        'note.',
                      ),
                    ),
                  ],
                  if (currencyChanged) ...[
                    const SizedBox(height: 6),
                    Text(
                      'The amount is now in $currency. Check it before '
                      'saving.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('expense-title'),
                    controller: _titleController,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 120,
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty) return 'Enter a title.';
                      if (t.length > 120) {
                        return friendlyMessageForKey('invalid_title');
                      }
                      return null;
                    },
                    decoration: const InputDecoration(
                      labelText: 'Expense Title',
                      hintText: 'e.g. Weekly groceries',
                      prefixIcon: Icon(Icons.receipt_long_rounded),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 18),
                  _scopeToggle(scheme, isDark, reason, canSwitch),
                  if (_scopeHint != null ||
                      (!canSwitch && _isGroup && !_locked)) ...[
                    const SizedBox(height: 10),
                    _hint(scheme, _scopeHint ?? reason!),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'Category',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  _categories(scheme, isDark),
                  const SizedBox(height: 18),
                  _dateTime(scheme, isDark),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('expense-note'),
                    controller: _noteController,
                    maxLines: 2,
                    maxLength: 500,
                    decoration: InputDecoration(
                      labelText: 'Note (optional)',
                      hintText: 'Add a description or location',
                      prefixIcon: const Icon(Icons.notes_rounded),
                      suffixIcon: _noteController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear note',
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: _noteController.clear,
                            ),
                    ),
                  ),
                  if (_formError != null) ...[
                    const SizedBox(height: 12),
                    _error(scheme, _formError!),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    key: const Key('expense-save'),
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _isEditing ? 'Save Changes' : 'Record Expense',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return Column(
      children: [
        Center(
          child: Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _isEditing ? 'Edit Expense' : 'Add Expense',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: scheme.onSurface,
              ),
            ),
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _amountCard(
    ColorScheme scheme,
    bool isDark,
    String currency,
    Group? group,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: isDark
            ? AppColors.darkCardElevated.withValues(alpha: 0.8)
            : AppColors.lightCardElevated,
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            MoneyFormat.symbolOf(currency),
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              key: const Key('expense-amount'),
              controller: _amountController,
              // Locked: someone who shares it left the group.
              readOnly: _locked,
              enabled: !_locked,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) => MoneyParser.validate(
                value,
                currency: currency,
                describe: friendlyMessage,
              ),
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
                color: scheme.onSurface,
              ),
              decoration: const InputDecoration(
                hintText: '0',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                filled: false,
              ),
            ),
          ),
          if (_isGroup && group != null)
            Tooltip(
              message: 'Group expenses use the group currency',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    currency,
                    key: const Key('expense-currency-locked'),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const Key('expense-currency'),
                value: _personalCurrency,
                items: [
                  for (final c in CurrencyInfo.all)
                    DropdownMenuItem(value: c.code, child: Text(c.code)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  AppHaptics.selection();
                  setState(() => _personalCurrency = value);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _scopeOption({
    required ColorScheme scheme,
    required bool isDark,
    required bool selected,
    required bool enabled,
    required IconData icon,
    required String label,
    required Color accent,
    required VoidCallback onTap,
  }) {
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final idle = enabled
        ? scheme.onSurfaceVariant
        : scheme.onSurfaceVariant.withValues(alpha: 0.5);
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? accent.withValues(alpha: 0.15) : null,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? accent : border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: selected ? accent : idle),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected ? accent : idle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _scopeToggle(
    ColorScheme scheme,
    bool isDark,
    String? reason,
    bool canSwitch,
  ) {
    return Row(
      children: [
        _scopeOption(
          scheme: scheme,
          isDark: isDark,
          selected: !_isGroup,
          enabled: !_isEditing || canSwitch || !_isGroup,
          icon: Icons.person_rounded,
          label: 'Personal',
          accent: scheme.primary,
          onTap: () => _chooseScope(group: false, reason: reason),
        ),
        const SizedBox(width: 12),
        _scopeOption(
          scheme: scheme,
          isDark: isDark,
          selected: _isGroup,
          enabled: canSwitch || _isGroup,
          icon: Icons.groups_rounded,
          label: 'Group Expense',
          accent: scheme.secondary,
          onTap: () => _chooseScope(group: true, reason: reason),
        ),
      ],
    );
  }

  Widget _hint(ColorScheme scheme, String text) {
    return Container(
      key: const Key('expense-scope-hint'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.3,
                color: scheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _error(ColorScheme scheme, String text) {
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('expense-form-error'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: scheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categories(ColorScheme scheme, bool isDark) {
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: AppConstants.categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, idx) {
          final cat = AppConstants.categories[idx];
          final isSelected = _category == cat.name;
          final catColor = AppColors.getCategoryColor(cat.name);
          return Semantics(
            button: true,
            selected: isSelected,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                AppHaptics.selection();
                setState(() => _category = cat.name);
              },
              child: Container(
                width: 76,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: isSelected
                      ? catColor.withValues(alpha: 0.18)
                      : (isDark
                            ? AppColors.darkCardElevated
                            : AppColors.lightCardElevated),
                  border: Border.all(
                    color: isSelected ? catColor : scheme.outlineVariant,
                    width: isSelected ? 1.5 : 0.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      cat.icon,
                      color: isSelected ? catColor : scheme.onSurfaceVariant,
                      size: 24,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cat.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected ? catColor : scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _dateTime(ColorScheme scheme, bool isDark) {
    Widget tile({
      required Key key,
      required IconData icon,
      required String text,
      required String tooltip,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Tooltip(
          message: tooltip,
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: isDark
                    ? AppColors.darkCardElevated.withValues(alpha: 0.6)
                    : AppColors.lightCardElevated,
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, color: scheme.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tile(
          key: const Key('expense-date'),
          icon: Icons.calendar_month_rounded,
          text: DateHelpers.formatDate(_spentAt),
          tooltip: 'Change date',
          onTap: _pickDate,
        ),
        const SizedBox(width: 10),
        tile(
          key: const Key('expense-time'),
          icon: Icons.schedule_rounded,
          text: DateHelpers.formatTime(_spentAt),
          tooltip: 'Change time',
          onTap: _pickTime,
        ),
      ],
    );
  }
}
