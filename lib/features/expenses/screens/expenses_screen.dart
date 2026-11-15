import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_helpers.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/money_format.dart';
import '../../../models/expense.dart';
import '../../../models/group.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/expense_provider.dart';
import '../../../providers/failure_reporter.dart';
import '../../../providers/group_detail_providers.dart';
import '../../../providers/groups_provider.dart';
import '../../shared/failure_retry.dart';
import 'add_edit_expense_sheet.dart';

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

  bool _canDelete(Expense expense) {
    final group = ref.read(activeGroupProvider);
    final inThisGroup = group != null && expense.groupId == group.id;
    return expense.canDelete(
      ref.read(currentUserIdProvider),
      isGroupAdmin: inThisGroup && group.isAdmin,
      canAddToGroup: inThisGroup && group.canAddExpenses,
    );
  }

  bool _canEdit(Expense expense) {
    final group = ref.read(activeGroupProvider);
    final inThisGroup = group != null && expense.groupId == group.id;
    return expense.canEdit(
      ref.read(currentUserIdProvider),
      canAddToGroup: inThisGroup && group.canAddExpenses,
    );
  }

  Future<void> _confirmDelete(Expense expense) async {
    AppHaptics.heavy();
    if (!_canDelete(expense)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            expense.isPersonal
                ? 'Only the creator can delete personal expenses.'
                : 'Only the payer or the group admin can delete this expense.',
          ),
        ),
      );
      return;
    }
    final key = ref.read(filteredExpenseKeyProvider);
    if (key == null) return;
    if (await _isLocked(expense)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyMessageForKey('expense_locked_member_left')),
        ),
      );
      return;
    }
    if (!mounted) return;
    final userId = ref.read(currentUserIdProvider);
    // Undo re-creates the expense as the current user, so it is offered
    // only to the payer (an admin deleting someone else's cannot undo).
    final canUndo = expense.userId != null && expense.userId == userId;
    final payerNote = canUndo
        ? ''
        : ' It was paid by someone else, so this cannot be undone.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text(
          '"${expense.title}" (${MoneyFormat.format(expense.amount)}) will be '
          'deleted${expense.isGroup ? ' for everyone in the group' : ''}.'
          '$payerNote',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final notifier = ref.read(expenseListProvider(key).notifier);
    // A failure is rolled back and shown once by the shell.
    final failure = await notifier.remove(expense);
    if (failure != null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Deleted "${expense.title}".'),
        action: canUndo
            ? SnackBarAction(
                label: 'Undo',
                onPressed: () => unawaited(_undoDelete(key, expense)),
              )
            : null,
      ),
    );
  }

  /// Whether [expense] is a group expense locked because someone who
  /// shares it left the group (the server would refuse the delete).
  Future<bool> _isLocked(Expense expense) async {
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

  /// Saves the deleted expense again (with a new id).
  Future<void> _undoDelete(ExpenseListKey key, Expense expense) async {
    final failure = await ref
        .read(expenseListProvider(key).notifier)
        .add(ExpenseDraft.fromExpense(expense));
    if (failure == null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restored "${expense.title}".')));
    }
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

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(expenseFilterProvider);
    final group = ref.watch(activeGroupProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final key = ref.watch(filteredExpenseKeyProvider);
    final listAsync = key == null
        ? const AsyncLoading<ExpenseListState>()
        : ref.watch(expenseListProvider(key));
    final list = listAsync.value;
    final filtered = list?.items ?? const <Expense>[];
    final members = ref.watch(activeGroupMembersProvider).value ?? const [];

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses Tracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              AppHaptics.light();
              unawaited(reload());
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by title...',
                prefixIcon: const Icon(Icons.search_rounded, size: 22),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _searchDebounce?.cancel();
                          setState(() {});
                          ref
                              .read(expenseFilterProvider.notifier)
                              .setSearch('');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),

          // Filter Segmented Tabs: All | Personal | Group (group mode only)
          if (group != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkCardElevated
                      : AppColors.lightCardElevated,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    _buildTypeTab('All', ExpenseTypeFilter.all, filter.type),
                    _buildTypeTab(
                      'Personal',
                      ExpenseTypeFilter.personal,
                      filter.type,
                    ),
                    _buildTypeTab(
                      'Group',
                      ExpenseTypeFilter.group,
                      filter.type,
                    ),
                  ],
                ),
              ),
            ),

          // Horizontal Category Chips
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              children: [
                _buildCategoryChip('All', null, filter.category == null),
                ...AppConstants.categories.map(
                  (c) => _buildCategoryChip(
                    c.name,
                    c.name,
                    filter.category == c.name,
                  ),
                ),
              ],
            ),
          ),

          // Expense List / Grouped View
          Expanded(
            child: (listAsync.hasError && filtered.isEmpty)
                ? Center(
                    child: FailureRetry(
                      error: listAsync.error!,
                      onRetry: () => unawaited(reload()),
                    ),
                  )
                : (list == null)
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                ? RefreshIndicator(
                    onRefresh: reload,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [_buildEmptyState(filter.isFiltered, group)],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: reload,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
                      itemCount: filtered.length + (list.hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= filtered.length) {
                          return _buildListFooter(key!, list);
                        }
                        final expense = filtered[index];
                        final showHeader =
                            index == 0 ||
                            DateHelpers.sectionHeader(expense.spentAt) !=
                                DateHelpers.sectionHeader(
                                  filtered[index - 1].spentAt,
                                );

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showHeader)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                                child: Text(
                                  DateHelpers.sectionHeader(expense.spentAt),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                    color: isDark
                                        ? AppColors.darkTextTertiary
                                        : AppColors.lightTextTertiary,
                                  ),
                                ),
                              ),
                            _buildExpenseTile(expense, members, isDark),
                          ],
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEditor,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        icon: const Icon(Icons.add_rounded, size: 24),
        label: const Text(
          'Add Expense',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ).animate().scale(delay: 200.ms, curve: Curves.easeOutBack),
    );
  }

  Widget _buildTypeTab(
    String label,
    ExpenseTypeFilter filterType,
    ExpenseTypeFilter current,
  ) {
    final isSelected = filterType == current;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onPrimaryColor = Theme.of(context).colorScheme.onPrimary;

    return Expanded(
      child: GestureDetector(
        onTap: () =>
            ref.read(expenseFilterProvider.notifier).setType(filterType),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? onPrimaryColor : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String label, String? category, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) =>
            ref.read(expenseFilterProvider.notifier).setCategory(category),
        selectedColor: AppColors.primaryCyan.withValues(alpha: 0.2),
        checkmarkColor: AppColors.primaryCyan,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? AppColors.primaryCyan : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected ? AppColors.primaryCyan : Colors.transparent,
          ),
        ),
      ),
    );
  }

  /// Loads the next page when the footer comes into view; shows Retry
  /// when that failed.
  Widget _buildListFooter(ExpenseListKey key, ExpenseListState list) {
    final failure = list.loadMoreFailure;
    if (failure != null) {
      return FailureRetry(
        error: failure,
        compact: true,
        onRetry: () =>
            unawaited(ref.read(expenseListProvider(key).notifier).loadMore()),
      );
    }
    if (!list.isLoadingMore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(ref.read(expenseListProvider(key).notifier).loadMore());
        }
      });
    }
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildExpenseTile(
    Expense expense,
    List<GroupMember> members,
    bool isDark,
  ) {
    final catColor = AppColors.getCategoryColor(expense.category);
    final catIcon = AppConstants.getCategoryIcon(expense.category);
    final canEdit = _canEdit(expense);
    final canDelete = _canDelete(expense);
    String payerLabel() {
      final payer = expense.userId;
      if (payer == null) return 'Former member';
      for (final m in members) {
        if (m.userId == payer) return m.label;
      }
      return 'Member';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        borderRadius: 18,
        padding: const EdgeInsets.all(14),
        onTap: () {
          if (canEdit) {
            _openEditor(expense: expense);
          } else {
            AppHaptics.selection();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Only the payer can edit this expense.'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        },
        child: Row(
          children: [
            // Category Icon with glow
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: catColor.withValues(alpha: 0.18),
                border: Border.all(color: catColor.withValues(alpha: 0.3)),
              ),
              child: Icon(catIcon, color: catColor, size: 22),
            ),
            const SizedBox(width: 14),

            // Title & Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${DateHelpers.formatShortDate(expense.spentAt)} • ${DateHelpers.formatTime(expense.spentAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.darkTextTertiary
                                : AppColors.lightTextTertiary,
                          ),
                        ),
                      ),
                      if (!expense.isPersonal) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryViolet.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              payerLabel(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryViolet,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Amount & Action Menu
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  MoneyFormat.format(expense.amount),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                if (canEdit || canDelete)
                  PopupMenuButton<String>(
                    tooltip: 'Expense actions',
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    onSelected: (val) {
                      if (val == 'edit') {
                        _openEditor(expense: expense);
                      } else if (val == 'delete') {
                        unawaited(_confirmDelete(expense));
                      }
                    },
                    itemBuilder: (ctx) => [
                      if (canEdit)
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Edit'),
                            ],
                          ),
                        ),
                      if (canDelete)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: AppColors.error,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Delete',
                                style: TextStyle(color: AppColors.error),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Two different empty states: nothing recorded yet (with a call to
  /// add the first expense) and nothing matching the filters (with a call
  /// to clear them).
  Widget _buildEmptyState(bool filtered, Group? group) {
    final scheme = Theme.of(context).colorScheme;
    final String title;
    final String body;
    if (filtered) {
      title = 'No matching expenses';
      body = 'Nothing matches your search or filters.';
    } else if (group != null) {
      title = 'No expenses yet';
      body = group.canAddExpenses
          ? 'Add the first expense for ${group.name} or your own spending.'
          : 'Expenses added to ${group.name} will show here.';
    } else {
      title = 'No expenses yet';
      body = 'Record your first expense to start tracking your spending.';
    }
    return Center(
      child: Padding(
        key: Key(filtered ? 'expenses-empty-filtered' : 'expenses-empty-new'),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary.withValues(alpha: 0.1),
              ),
              child: Icon(
                filtered ? Icons.search_off_rounded : Icons.savings_outlined,
                size: 48,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (filtered)
              OutlinedButton.icon(
                onPressed: () {
                  _searchDebounce?.cancel();
                  _searchController.clear();
                  ref.read(expenseFilterProvider.notifier).clear();
                },
                icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                label: const Text('Clear filters'),
              )
            else
              ElevatedButton.icon(
                onPressed: _openEditor,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add your first expense'),
              ),
          ],
        ),
      ),
    );
  }
}
