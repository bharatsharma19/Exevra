import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_helpers.dart';
import '../../../core/utils/haptics.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/expense_provider.dart';
import '../../../providers/insights_provider.dart';
import '../../expenses/screens/add_edit_expense_sheet.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  void _showGroupSwitcher(BuildContext context, WidgetRef ref) {
    AppHaptics.selection();
    final expenseState = ref.read(expenseProvider);
    final userGroups = expenseState.userGroups;
    final currentGroupId = expenseState.currentGroup?.id;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Switch Active Group',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: currentGroupId == null
                      ? AppColors.primaryCyan
                      : Colors.grey.withValues(alpha: 0.2),
                  child: Icon(
                    Icons.person_rounded,
                    color: currentGroupId == null ? Colors.black : Colors.grey,
                  ),
                ),
                title: const Text(
                  'Personal Outflow Only',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: currentGroupId == null
                    ? const Icon(Icons.check_rounded, color: AppColors.primaryCyan)
                    : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  ref.read(expenseProvider.notifier).switchGroup(null);
                },
              ),
              if (userGroups.isNotEmpty) const Divider(),
              ...userGroups.map((g) {
                final isCurrent = g.id == currentGroupId;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: isCurrent
                        ? AppColors.primaryViolet
                        : Colors.grey.withValues(alpha: 0.2),
                    child: Icon(
                      Icons.groups_rounded,
                      color: isCurrent ? Colors.white : Colors.grey,
                    ),
                  ),
                  title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: isCurrent
                      ? const Icon(Icons.check_rounded, color: AppColors.primaryViolet)
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    ref.read(expenseProvider.notifier).switchGroup(g.id);
                  },
                );
              }),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    context.push('/profile');
                  },
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text('Manage Groups in Profile'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final expenseState = ref.watch(expenseProvider);
    final insightState = ref.watch(insightProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final profile = authState.profile;
    final resolvedDisplayName = (profile?.displayName != null && profile!.displayName.trim().isNotEmpty)
        ? profile.displayName
        : (authState.user?.userMetadata?['full_name'] as String? ?? authState.user?.email?.split('@').first ?? 'User');
    final currency = profile?.currency ?? AppConstants.defaultCurrency;
    final group = expenseState.currentGroup;

    final currentUserId = authState.user?.id;
    final totalSpent = expenseState.userTotalOutflow(currentUserId);
    final personalSpent = expenseState.personalSpent;
    final groupSpent = expenseState.groupSpent;
    final recentExpenses = expenseState.expenses.take(5).toList();

    return Scaffold(
      body: Stack(
        children: [
          // Background ambient gradient glow
          Positioned(
            top: -100,
            left: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryCyan.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            top: 200,
            right: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryViolet.withValues(alpha: 0.08),
              ),
            ),
          ),

          SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                await ref.read(expenseProvider.notifier).loadAll();
                await ref.read(insightProvider.notifier).loadInsights();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Bar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getGreeting(),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              resolvedDisplayName,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                              ),
                            ),
                          ],
                        ),
                        // Group badge or avatar
                        GestureDetector(
                          onTap: () => _showGroupSwitcher(context, ref),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkCardElevated : AppColors.lightCardElevated,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: group != null ? AppColors.primaryViolet : AppColors.primaryCyan,
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  group != null ? Icons.groups_rounded : Icons.person_rounded,
                                  size: 16,
                                  color: group != null ? AppColors.primaryViolet : AppColors.primaryCyan,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  group != null ? group.name : 'Personal',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: group != null ? AppColors.primaryViolet : AppColors.primaryCyan,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ).animate().fadeIn(duration: 300.ms),

                    const SizedBox(height: 20),

                    // Main Total Expense Neon Card
                    GlassCard(
                      borderRadius: 24,
                      gradient: AppColors.darkCardGradient,
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'TOTAL OUTFLOW',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.8,
                                  color: AppColors.primaryCyan,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryCyan.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  currency,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primaryCyan,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            CurrencyFormatter.format(totalSpent, currencyCode: currency),
                            style: const TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                              color: Colors.white,
                            ),
                          ).animate().fadeIn(delay: 150.ms).slideX(begin: -0.1, end: 0),
                          const SizedBox(height: 16),

                          // Personal vs Group Split Bar
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryCyan)),
                                        const SizedBox(width: 6),
                                        const Text('Personal', style: TextStyle(fontSize: 12, color: Colors.white70)),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      CurrencyFormatter.format(personalSpent, currencyCode: currency),
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                              Container(width: 1, height: 32, color: Colors.white12),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryViolet)),
                                        const SizedBox(width: 6),
                                        const Text('Group Share', style: TextStyle(fontSize: 12, color: Colors.white70)),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      CurrencyFormatter.format(groupSpent, currencyCode: currency),
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0),

                    const SizedBox(height: 18),

                    // Quick Actions Row
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              AppHaptics.selection();
                              AddEditExpenseSheet.show(context);
                            },
                            child: GlassCard(
                              borderRadius: 18,
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.add_circle_outline_rounded, color: AppColors.primaryCyan, size: 20),
                                  SizedBox(width: 8),
                                  Text('Quick Add', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              AppHaptics.selection();
                              context.push('/chat');
                            },
                            child: GlassCard(
                              borderRadius: 18,
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.auto_awesome_rounded, color: AppColors.primaryViolet, size: 20),
                                  SizedBox(width: 8),
                                  Text('AI Advisor', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ).animate().fadeIn(delay: 250.ms),

                    if (group != null && expenseState.settlements.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      GlassCard(
                        borderRadius: 20,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.account_balance_wallet_rounded,
                                      size: 18,
                                      color: AppColors.primaryEmerald,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Group Balances & Debts',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                GestureDetector(
                                  onTap: () => context.push('/profile'),
                                  child: const Text(
                                    'Settle Up →',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryCyan,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ...expenseState.settlements.take(2).map((d) {
                              final iOwe = d.fromUserId == currentUserId;
                              final owedToMe = d.toUserId == currentUserId;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Icon(
                                      iOwe
                                          ? Icons.arrow_circle_up_rounded
                                          : (owedToMe
                                              ? Icons.arrow_circle_down_rounded
                                              : Icons.swap_horiz_rounded),
                                      size: 16,
                                      color: iOwe
                                          ? AppColors.primaryRose
                                          : (owedToMe
                                              ? AppColors.primaryEmerald
                                              : AppColors.primaryCyan),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        iOwe
                                            ? 'You owe ${d.toUserName}'
                                            : (owedToMe
                                                ? '${d.fromUserName} owes you'
                                                : '${d.fromUserName} owes ${d.toUserName}'),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      CurrencyFormatter.format(
                                        d.amount,
                                        currencyCode: currency,
                                      ),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: iOwe
                                            ? AppColors.primaryRose
                                            : (owedToMe
                                                ? AppColors.primaryEmerald
                                                : null),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ).animate().fadeIn(delay: 280.ms),
                    ],

                    const SizedBox(height: 24),

                    // Highlights Carousel
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Telemetry Highlights',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => context.push('/insights'),
                          child: Text(
                            'Full Analytics →',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: GlassCard(
                            borderRadius: 18,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.speed_rounded, color: AppColors.primaryEmerald, size: 22),
                                const SizedBox(height: 10),
                                Text(
                                  'Daily Average',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  CurrencyFormatter.format(insightState.insight.averageDaily, currencyCode: currency),
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GlassCard(
                            borderRadius: 18,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.pie_chart_outline_rounded, color: AppColors.primaryAmber, size: 22),
                                const SizedBox(height: 10),
                                Text(
                                  'Top Category',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  insightState.insight.categoryBreakdown.isNotEmpty
                                      ? insightState.insight.categoryBreakdown.first.category
                                      : 'None',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ).animate().fadeIn(delay: 300.ms),

                    const SizedBox(height: 26),

                    // Recent Transactions Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Recent Outflows',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => context.push('/expenses'),
                          child: Text(
                            'View All',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (expenseState.isLoading && expenseState.expenses.isEmpty) ...[
                      GlassCard(
                        borderRadius: 20,
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    ] else if (recentExpenses.isEmpty) ...[
                      GlassCard(
                        borderRadius: 20,
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Column(
                            children: const [
                              Icon(Icons.receipt_long_outlined, size: 36, color: Colors.grey),
                              SizedBox(height: 8),
                              Text('No expenses logged yet.', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      ...recentExpenses.map((expense) {
                        final catColor = AppColors.getCategoryColor(expense.category);
                        final catIcon = AppConstants.getCategoryIcon(expense.category);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassCard(
                            borderRadius: 18,
                            padding: const EdgeInsets.all(14),
                            onTap: () {
                              AppHaptics.selection();
                              AddEditExpenseSheet.show(context, expense: expense);
                            },
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: catColor.withValues(alpha: 0.16),
                                  ),
                                  child: Icon(catIcon, color: catColor, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        expense.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${expense.category} • ${DateHelpers.formatTime(expense.date)} • ${DateHelpers.formatRelative(expense.date)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  CurrencyFormatter.format(expense.amount, currencyCode: currency),
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          AppHaptics.selection();
          AddEditExpenseSheet.show(context);
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 4,
        child: const Icon(Icons.add_rounded, size: 28),
      ).animate().scale(delay: 400.ms, curve: Curves.easeOutBack),
    );
  }
}
