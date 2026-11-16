import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/date_helpers.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../expense_categories.dart';
import 'inline_notice.dart';

/// Personal or group, as a segmented control.
///
/// An option the user cannot pick stays tappable and shows a lock icon, so
/// a tap can explain why ([onSelected] decides); its tooltip says so too.
class ExpenseScopeSelector extends StatelessWidget {
  /// Creates the selector.
  const ExpenseScopeSelector({
    required this.isGroup,
    required this.onSelected,
    this.personalLocked = false,
    this.groupLocked = false,
    this.hint,
    this.caption,
    super.key,
  });

  /// Why the other option is unavailable, shown as a notice.
  final String? hint;

  /// Shown under the selector when there is no [hint] (the group).
  final String? caption;

  /// Whether Group is selected.
  final bool isGroup;

  /// Called with true for Group and false for Personal.
  final ValueChanged<bool> onSelected;

  /// Personal cannot be chosen (shows a lock).
  final bool personalLocked;

  /// Group cannot be chosen (shows a lock).
  final bool groupLocked;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selector = Semantics(
      label: l10n.expensesScopeLabel,
      container: true,
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: false,
              icon: Icon(
                personalLocked
                    ? Icons.lock_outline_rounded
                    : Icons.person_rounded,
              ),
              tooltip: personalLocked ? l10n.expensesScopeUnavailable : null,
              label: Text(
                l10n.expensesScopePersonal,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(
                groupLocked ? Icons.lock_outline_rounded : Icons.groups_rounded,
              ),
              tooltip: groupLocked ? l10n.expensesScopeUnavailable : null,
              label: Text(
                l10n.expensesScopeGroup,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          selected: {isGroup},
          onSelectionChanged: (selection) => onSelected(selection.first),
        ),
      ),
    );
    final hint = this.hint;
    final caption = this.caption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        selector,
        if (hint != null) ...[
          const SizedBox(height: AppSpacing.sm),
          InlineNotice(key: const Key('expense-scope-hint'), message: hint),
        ] else if (caption != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(caption, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}

/// The categories as chips with their icons; wraps onto more lines at
/// large text sizes instead of clipping.
class ExpenseCategoryPicker extends StatelessWidget {
  /// Creates the picker.
  const ExpenseCategoryPicker({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  /// The selected category name.
  final String selected;

  /// Called with the tapped category name.
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = context.l10n;
    final chips = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        for (final category in AppConstants.categories)
          ChoiceChip(
            key: Key('expense-category-${category.name}'),
            avatar: Icon(
              category.icon,
              size: AppSizes.iconSm,
              color: palette.categoryColor(category.name),
            ),
            showCheckmark: false,
            label: Text(categoryLabel(l10n, category.name)),
            selected: selected == category.name,
            onSelected: (_) => onSelected(category.name),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: l10n.expensesCategoryLabel,
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        ),
        chips,
      ],
    );
  }
}

/// Date and time buttons for an expense that open the pickers; stacked on
/// narrow screens and at large text sizes.
class ExpenseDateTimeFields extends StatelessWidget {
  /// Creates the fields.
  const ExpenseDateTimeFields({
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// Local wall-clock date and time.
  final DateTime value;

  /// Called with the new local date and time.
  final ValueChanged<DateTime> onChanged;

  Future<void> _pickDate(BuildContext context) async {
    AppHaptics.selection();
    final now = DateTime.now();
    final first = DateTime(2000);
    final last = DateTime(now.year + 1, now.month, now.day);
    var initial = DateTime(value.year, value.month, value.day);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null) return;
    onChanged(DateHelpers.combineLocal(picked, value.hour, value.minute));
  }

  Future<void> _pickTime(BuildContext context) async {
    AppHaptics.selection();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    if (picked == null) return;
    onChanged(DateHelpers.combineLocal(value, picked.hour, picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final date = _PickerButton(
      key: const Key('expense-date'),
      icon: Icons.calendar_month_rounded,
      text: DateHelpers.formatDate(value),
      tooltip: l10n.expensesChangeDate,
      onPressed: () => _pickDate(context),
    );
    final time = _PickerButton(
      key: const Key('expense-time'),
      icon: Icons.schedule_rounded,
      text: DateHelpers.formatTime(value),
      tooltip: l10n.expensesChangeTime,
      onPressed: () => _pickTime(context),
    );
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 340 || scale >= 1.5) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              date,
              const SizedBox(height: AppSpacing.sm),
              time,
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 3, child: date),
            const SizedBox(width: AppSpacing.sm),
            Expanded(flex: 2, child: time),
          ],
        );
      },
    );
  }
}

/// The sheet's title (a heading) and its Close button.
class ExpenseSheetHeader extends StatelessWidget {
  /// Creates the header.
  const ExpenseSheetHeader({required this.title, super.key});

  /// "Add expense" or "Edit expense".
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
          AppIconButton(
            icon: Icons.close_rounded,
            tooltip: context.l10n.close,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

/// The expense title, required and at most 120 characters.
class ExpenseTitleField extends StatelessWidget {
  /// Creates the field.
  const ExpenseTitleField({required this.controller, super.key});

  /// Title text.
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextFormField(
      key: const Key('expense-title'),
      controller: controller,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.next,
      maxLength: 120,
      validator: (v) {
        final t = v?.trim() ?? '';
        if (t.isEmpty) return l10n.expensesTitleRequired;
        if (t.length > 120) return friendlyMessageForKey('invalid_title');
        return null;
      },
      decoration: InputDecoration(
        labelText: l10n.expensesTitleLabel,
        hintText: l10n.expensesTitleHint,
        prefixIcon: const Icon(Icons.receipt_long_rounded),
        counterText: '',
      ),
    );
  }
}

/// The optional note with a clear button.
class ExpenseNoteField extends StatelessWidget {
  /// Creates the field.
  const ExpenseNoteField({required this.controller, super.key});

  /// Note text.
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextFormField(
      key: const Key('expense-note'),
      controller: controller,
      maxLines: 3,
      minLines: 1,
      maxLength: 500,
      decoration: InputDecoration(
        labelText: l10n.expensesNoteLabel,
        hintText: l10n.expensesNoteHint,
        prefixIcon: const Icon(Icons.notes_rounded),
        suffixIcon: controller.text.isEmpty
            ? null
            : AppIconButton(
                icon: Icons.clear_rounded,
                tooltip: l10n.expensesClearNote,
                onPressed: controller.clear,
              ),
      ),
    );
  }
}

class _PickerButton extends StatelessWidget {
  const _PickerButton({
    required this.icon,
    required this.text,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String text;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppSizes.minTapTarget),
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: AppSizes.iconSm),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
