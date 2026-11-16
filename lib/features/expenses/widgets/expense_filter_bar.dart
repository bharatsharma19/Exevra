import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/expense_provider.dart';
import '../expense_categories.dart';
import '../expense_date_filter.dart';

/// Search, the personal/group switch (in group mode), and the date and
/// category filters of the expenses screen.
class ExpenseFilterBar extends ConsumerWidget {
  /// Creates the bar.
  const ExpenseFilterBar({
    required this.searchController,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.showTypeFilter,
    super.key,
  });

  /// The search text.
  final TextEditingController searchController;

  /// Called on every search edit.
  final ValueChanged<String> onSearchChanged;

  /// Called by the clear button.
  final VoidCallback onSearchCleared;

  /// Whether to show All / Personal / Group (only with an active group).
  final bool showTypeFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final filter = ref.watch(expenseFilterProvider);
    final notifier = ref.read(expenseFilterProvider.notifier);
    final preset = ref.watch(expenseDatePresetProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.sm,
            AppSpacing.gutter,
            AppSpacing.xs,
          ),
          child: TextField(
            key: const Key('expenses-search'),
            controller: searchController,
            onChanged: onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: l10n.expensesSearchLabel,
              hintText: l10n.expensesSearchHint,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : AppIconButton(
                      icon: Icons.clear_rounded,
                      tooltip: l10n.expensesClearSearch,
                      onPressed: onSearchCleared,
                    ),
            ),
          ),
        ),
        if (showTypeFilter)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.gutter,
              vertical: AppSpacing.xs,
            ),
            child: SegmentedButton<ExpenseTypeFilter>(
              key: const Key('expenses-type'),
              showSelectedIcon: false,
              segments: [
                for (final (type, label) in [
                  (ExpenseTypeFilter.all, l10n.expensesTypeAll),
                  (ExpenseTypeFilter.personal, l10n.expensesTypePersonal),
                  (ExpenseTypeFilter.group, l10n.expensesTypeGroup),
                ])
                  ButtonSegment(
                    value: type,
                    label: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              selected: {filter.type},
              onSelectionChanged: (selection) {
                AppHaptics.selection();
                notifier.setType(selection.first);
              },
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.gutter,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              FilterChip(
                key: const Key('expenses-date-filter'),
                avatar: const Icon(
                  Icons.calendar_month_rounded,
                  size: AppSizes.iconSm,
                ),
                showCheckmark: false,
                selected: preset != ExpenseDatePreset.any,
                label: Text(datePresetLabel(l10n, preset)),
                tooltip: l10n.expensesDateFilterTooltip,
                onSelected: (_) => _pickDate(context, ref, preset),
              ),
              const SizedBox(width: AppSpacing.sm),
              _CategoryChip(
                label: l10n.expensesAllCategories,
                selected: filter.category == null,
                onSelected: () => notifier.setCategory(null),
              ),
              for (final c in AppConstants.categories) ...[
                const SizedBox(width: AppSpacing.sm),
                _CategoryChip(
                  label: categoryLabel(l10n, c.name),
                  icon: c.icon,
                  iconColor: context.palette.categoryColor(c.name),
                  selected: filter.category == c.name,
                  onSelected: () => notifier.setCategory(
                    filter.category == c.name ? null : c.name,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    WidgetRef ref,
    ExpenseDatePreset current,
  ) async {
    AppHaptics.selection();
    final picked = await showAppSheet<ExpenseDatePreset>(
      context: context,
      builder: (context) {
        final l10n = context.l10n;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: l10n.expensesDateFilterTitle,
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            ),
            for (final preset in ExpenseDatePreset.values)
              AppListTile(
                key: Key('expenses-date-${preset.name}'),
                title: datePresetLabel(l10n, preset),
                selected: preset == current,
                trailing: preset == current
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(preset),
              ),
          ],
        );
      },
    );
    if (picked != null) {
      ref.read(expenseDatePresetProvider.notifier).set(picked);
    }
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
    this.iconColor,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      avatar: icon == null
          ? null
          : Icon(icon, size: AppSizes.iconSm, color: iconColor),
      onSelected: (_) {
        AppHaptics.selection();
        onSelected();
      },
    );
  }
}
