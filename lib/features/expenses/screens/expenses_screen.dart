import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_helpers.dart';
import '../../../core/utils/haptics.dart';
import '../../../models/expense_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/expense_provider.dart';
import 'add_edit_expense_sheet.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _confirmDelete(Expense expense) {
    AppHaptics.heavy();
    final auth = ref.read(authNotifierProvider);
    final currentUserId = auth.user?.id ?? 'demo-user-id';
    final isGroupAdmin = ref.read(expenseProvider).currentGroup?.isAdmin(currentUserId) ?? true;

    if (!expense.canDelete(currentUserId, isGroupAdmin) && currentUserId != 'demo-user-id') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            expense.isPersonal
                ? 'Only the creator can delete personal expenses.'
                : 'Group expenses can ONLY be deleted by the Group Admin.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Expense?'),
        content: Text('Are you sure you want to delete "${expense.title}"? This action cannot be reversed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(expenseProvider.notifier).deleteExpense(expense.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expenseState = ref.watch(expenseProvider);
    final auth = ref.watch(authNotifierProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currency = auth.profile?.currency ?? AppConstants.defaultCurrency;
    final filtered = expenseState.filteredExpenses;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses Tracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              AppHaptics.light();
              ref.read(expenseProvider.notifier).loadAll();
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
              onChanged: (val) => ref.read(expenseProvider.notifier).setSearchQuery(val),
              decoration: InputDecoration(
                hintText: 'Search by title, category, or note...',
                prefixIcon: const Icon(Icons.search_rounded, size: 22),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(expenseProvider.notifier).setSearchQuery('');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),

          // Filter Segmented Tabs: All | Personal | Group
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCardElevated : AppColors.lightCardElevated,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  _buildTypeTab('All', ExpenseTypeFilter.all, expenseState.filter.type),
                  _buildTypeTab('Personal', ExpenseTypeFilter.personal, expenseState.filter.type),
                  _buildTypeTab('Group', ExpenseTypeFilter.group, expenseState.filter.type),
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
                _buildCategoryChip('All', expenseState.filter.category == 'All'),
                ...AppConstants.categories.map(
                  (c) => _buildCategoryChip(c.name, expenseState.filter.category == c.name),
                ),
              ],
            ),
          ),

          // Expense List / Grouped View
          Expanded(
            child: (expenseState.isLoading && expenseState.expenses.isEmpty)
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: () => ref.read(expenseProvider.notifier).loadAll(),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final expense = filtered[index];
                            final showHeader = index == 0 ||
                                DateHelpers.getDateSectionHeader(expense.date) !=
                                    DateHelpers.getDateSectionHeader(filtered[index - 1].date);

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (showHeader)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                                    child: Text(
                                      DateHelpers.getDateSectionHeader(expense.date),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                        color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                                      ),
                                    ),
                                  ),
                                _buildExpenseTile(expense, currency, isDark),
                              ],
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          AppHaptics.selection();
          AddEditExpenseSheet.show(context);
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        icon: const Icon(Icons.add_rounded, size: 24),
        label: const Text('Add Expense', style: TextStyle(fontWeight: FontWeight.w700)),
      ).animate().scale(delay: 200.ms, curve: Curves.easeOutBack),
    );
  }

  Widget _buildTypeTab(String label, ExpenseTypeFilter filterType, ExpenseTypeFilter current) {
    final isSelected = filterType == current;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onPrimaryColor = Theme.of(context).colorScheme.onPrimary;

    return Expanded(
      child: GestureDetector(
        onTap: () => ref.read(expenseProvider.notifier).setTypeFilter(filterType),
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

  Widget _buildCategoryChip(String categoryName, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(categoryName),
        selected: isSelected,
        onSelected: (_) => ref.read(expenseProvider.notifier).setCategoryFilter(categoryName),
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

  Widget _buildExpenseTile(Expense expense, String currency, bool isDark) {
    final catColor = AppColors.getCategoryColor(expense.category);
    final catIcon = AppConstants.getCategoryIcon(expense.category);
    final auth = ref.watch(authNotifierProvider);
    final currentUserId = auth.user?.id ?? 'demo-user-id';
    final isGroupAdmin = ref.watch(expenseProvider).currentGroup?.isAdmin(currentUserId) ?? true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        borderRadius: 18,
        padding: const EdgeInsets.all(14),
        onTap: () {
          AppHaptics.selection();
          if (expense.canEdit(currentUserId) || currentUserId == 'demo-user-id') {
            AddEditExpenseSheet.show(context, expense: expense);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Only the creator can edit this expense.'),
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
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        '${DateHelpers.formatShortDate(expense.date)} • ${DateHelpers.formatTime(expense.date)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                        ),
                      ),
                      if (!expense.isPersonal) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppColors.primaryViolet.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            expense.creatorName ?? 'Group',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryViolet,
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
                  CurrencyFormatter.format(expense.amount, currencyCode: currency),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_horiz_rounded, size: 20, color: Colors.grey),
                  onSelected: (val) {
                    if (val == 'edit') {
                      AddEditExpenseSheet.show(context, expense: expense);
                    } else if (val == 'delete') {
                      _confirmDelete(expense);
                    }
                  },
                  itemBuilder: (ctx) => [
                    if (expense.canEdit(currentUserId) || currentUserId == 'demo-user-id')
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
                    if (expense.canDelete(currentUserId, isGroupAdmin) || currentUserId == 'demo-user-id')
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: AppColors.error)),
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryCyan.withValues(alpha: 0.1),
              ),
              child: const Icon(Icons.savings_outlined, size: 48, color: AppColors.primaryCyan),
            ),
            const SizedBox(height: 18),
            const Text(
              'No Expenses Found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'No expenses match your active filters or search terms.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
