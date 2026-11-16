import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/date_helpers.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/expense.dart';
import '../../../models/group.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/expense_provider.dart';
import '../../../providers/failure_reporter.dart';
import '../../../providers/group_detail_providers.dart';
import '../../../providers/groups_provider.dart';
import '../expense_actions.dart';
import '../expense_date_filter.dart';
import '../widgets/expense_filter_bar.dart';
import '../widgets/expense_tile.dart';
import '../widgets/inline_notice.dart';
import 'add_edit_expense_sheet.dart';

/// The expenses tab: search and filters, the date-grouped list with
/// pull-to-refresh and paging, and add, edit and delete (with Undo).
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchController.text = ref.read(expenseFilterProvider).search;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Searches on the server once typing pauses.
  void _onSearchChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) ref.read(expenseFilterProvider.notifier).setSearch(value);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {});
    ref.read(expenseFilterProvider.notifier).setSearch('');
  }

  void _clearFilters() {
    _searchDebounce?.cancel();
    _searchController.clear();
    ref.read(expenseFilterProvider.notifier).clear();
    ref.read(expenseDatePresetProvider.notifier).set(ExpenseDatePreset.any);
  }

  /// Group rules for [expense]: whether it is in the active group, whether
  /// the user is its admin and whether they can add to it.
  ({bool admin, bool canAdd}) _rights(Expense expense) {
    final group = ref.read(activeGroupProvider);
    final inGroup = group != null && expense.groupId == group.id;
    return (
      admin: inGroup && group.isAdmin,
      canAdd: inGroup && group.canAddExpenses,
    );
  }

  bool _canEdit(Expense expense) => expense.canEdit(
    ref.read(currentUserIdProvider),
    canAddToGroup: _rights(expense).canAdd,
  );

  bool _canDelete(Expense expense) {
    final rights = _rights(expense);
    return expense.canDelete(
      ref.read(currentUserIdProvider),
      isGroupAdmin: rights.admin,
      canAddToGroup: rights.canAdd,
    );
  }

  void _openEditor({Expense? expense}) {
    AppHaptics.selection();
    unawaited(
      AddEditExpenseSheet.show(
        context,
        expense: expense,
        listKey: ref.read(filteredExpenseKeyProvider),
      ),
    );
  }

  void _onTap(Expense expense) {
    if (_canEdit(expense)) {
      _openEditor(expense: expense);
      return;
    }
    AppHaptics.selection();
    AppSnackbar.showInfo(
      context.l10n.expensesOnlyPayerCanEdit,
      messenger: ScaffoldMessenger.maybeOf(context),
    );
  }

  void _onAction(Expense expense, ExpenseAction action) {
    switch (action) {
      case ExpenseAction.edit:
        _openEditor(expense: expense);
      case ExpenseAction.delete:
        final key = ref.read(filteredExpenseKeyProvider);
        if (key == null) return;
        unawaited(
          deleteExpenseWithUndo(context, ref, expense: expense, key: key),
        );
    }
  }

  String? _payerLabel(Expense expense, List<GroupMember> members, bool mixed) {
    final l10n = context.l10n;
    if (expense.isPersonal) return mixed ? l10n.expensesPersonalTag : null;
    final payer = expense.userId;
    if (payer == null) return l10n.expensesPaidByFormer;
    if (payer == ref.read(currentUserIdProvider)) return l10n.expensesPaidByYou;
    for (final m in members) {
      if (m.userId == payer) return l10n.expensesPaidBy(m.label);
    }
    return l10n.expensesPaidByMember;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filter = ref.watch(expenseFilterProvider);
    final preset = ref.watch(expenseDatePresetProvider);
    final range = dateRangeOf(preset, DateTime.now());
    final group = ref.watch(activeGroupProvider);
    final key = ref.watch(filteredExpenseKeyProvider);
    final listAsync = key == null
        ? const AsyncLoading<ExpenseListState>()
        : ref.watch(expenseListProvider(key));
    final list = listAsync.value;
    final members = ref.watch(activeGroupMembersProvider).value ?? const [];
    final filtered = preset != ExpenseDatePreset.any || filter.isFiltered;
    final mixed = group != null && filter.type == ExpenseTypeFilter.all;

    Future<void> reload() async {
      if (key == null) return;
      final failure = await ref
          .read(expenseListProvider(key).notifier)
          .reload();
      // The first load's failure is the error state; later ones keep the
      // rows and are shown once by the shell.
      if (failure != null && list != null && mounted) {
        ref.read(failureReporterProvider.notifier).report(failure);
      }
    }

    final Widget body;
    if (listAsync.hasError && (list?.items.isEmpty ?? true)) {
      final error = listAsync.error;
      body = ErrorState(
        title: l10n.expensesLoadErrorTitle,
        message: friendlyMessage(
          error is AppFailure ? error : const AppFailure.unknown(),
        ),
        onRetry: () => unawaited(reload()),
      );
    } else if (list == null) {
      body = const SkeletonList();
    } else {
      body = _ExpenseList(
        list: list,
        range: range,
        filtered: filtered,
        onRefresh: reload,
        onLoadMore: () =>
            ref.read(expenseListProvider(key!).notifier).loadMore(),
        empty: filtered
            ? EmptyState(
                key: const Key('expenses-empty-filtered'),
                icon: Icons.search_off_rounded,
                title: l10n.expensesEmptyFilteredTitle,
                message: l10n.expensesEmptyFilteredMessage,
                actionLabel: l10n.expensesClearFilters,
                actionIcon: Icons.filter_alt_off_rounded,
                onAction: _clearFilters,
              )
            : EmptyState(
                key: const Key('expenses-empty-new'),
                icon: Icons.savings_outlined,
                title: l10n.expensesEmptyTitle,
                message: group == null
                    ? l10n.expensesEmptyMessage
                    : group.canAddExpenses
                    ? l10n.expensesEmptyGroupMessage(group.name)
                    : l10n.expensesEmptyViewerMessage(group.name),
                actionLabel: l10n.expensesAddFirst,
                onAction: _openEditor,
              ),
        tileOf: (expense) => ExpenseTile(
          key: ValueKey('expense-${expense.id}'),
          expense: expense,
          payerLabel: _payerLabel(expense, members, mixed),
          canEdit: _canEdit(expense),
          canDelete: _canDelete(expense),
          onTap: () => _onTap(expense),
          onAction: (action) => _onAction(expense, action),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.expensesTitle),
        actions: [
          AppIconButton(
            icon: Icons.refresh_rounded,
            tooltip: l10n.expensesRefresh,
            onPressed: () {
              AppHaptics.light();
              unawaited(reload());
            },
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ExpenseFilterBar(
              searchController: _searchController,
              onSearchChanged: _onSearchChanged,
              onSearchCleared: _clearSearch,
              showTypeFilter: group != null && group.canRead,
            ),
            Expanded(child: body),
          ],
        ),
      ),
      floatingActionButton: SnackbarClearance(
        child: FloatingActionButton.extended(
          key: const Key('expenses-add'),
          onPressed: _openEditor,
          tooltip: l10n.expensesAdd,
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.expensesAdd),
        ),
      ),
    );
  }
}

/// The loaded list: date headers, rows, the paging footer, the result
/// count while filtering, and the empty state, all under pull-to-refresh.
class _ExpenseList extends StatelessWidget {
  const _ExpenseList({
    required this.list,
    required this.range,
    required this.filtered,
    required this.onRefresh,
    required this.onLoadMore,
    required this.empty,
    required this.tileOf,
  });

  final ExpenseListState list;
  final LocalDateRange? range;
  final bool filtered;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final Widget empty;
  final Widget Function(Expense expense) tileOf;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final range = this.range;
    final items = list.items.where((e) => inDateRange(e, range)).toList();
    // Newest first: once the oldest loaded expense is before the range,
    // every expense in the range is loaded.
    final oldest = list.items.isEmpty ? null : list.items.last.spentAt;
    final needMore =
        list.hasMore &&
        (range == null ||
            oldest == null ||
            !oldest.toLocal().isBefore(range.start));

    if (items.isEmpty && !needMore) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: empty,
            ),
          ),
        ),
      );
    }

    final header = filtered && !needMore;
    final offset = header ? 1 : 0;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.xs,
          AppSpacing.gutter,
          96,
        ),
        itemCount: offset + items.length + (needMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (header && index == 0) {
            return Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Text(
                  l10n.expensesResultCount(items.length),
                  key: const Key('expenses-result-count'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.palette.textSecondary,
                  ),
                ),
              ),
            );
          }
          final i = index - offset;
          if (i >= items.length) {
            return _Footer(list: list, onLoadMore: onLoadMore);
          }
          final expense = items[i];
          final section = DateHelpers.sectionHeader(expense.spentAt);
          final showHeader =
              i == 0 ||
              section != DateHelpers.sectionHeader(items[i - 1].spentAt);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showHeader)
                SectionHeader(
                  title: section,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xs,
                    AppSpacing.lg,
                    AppSpacing.xs,
                    AppSpacing.sm,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: tileOf(expense),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Loads the next page when it comes into view; Retry when that failed.
class _Footer extends StatelessWidget {
  const _Footer({required this.list, required this.onLoadMore});

  final ExpenseListState list;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    final failure = list.loadMoreFailure;
    if (failure != null) {
      return CompactRetry(
        error: failure,
        onRetry: () => unawaited(onLoadMore()),
      );
    }
    if (!list.isLoadingMore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) unawaited(onLoadMore());
      });
    }
    return const SkeletonList(itemCount: 2);
  }
}
