import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/router/navigation.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_helpers.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/money_format.dart';
import '../../../models/balance.dart';
import '../../../models/expense.dart';
import '../../../models/insights.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/expense_provider.dart';
import '../../../providers/group_detail_providers.dart';
import '../../../providers/groups_provider.dart';
import '../../../providers/insights_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../shared/failure_retry.dart';
import '../../expenses/screens/add_edit_expense_sheet.dart';
import '../../onboarding/first_expense_nudge.dart';

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
    final groupsState = ref.read(currentGroupsProvider);
    // Pending join requests cannot be opened until an admin approves.
    final userGroups = groupsState?.approvedGroups ?? const [];
    final currentGroupId = ref.read(activeGroupProvider)?.id;

    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
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
                      color: currentGroupId == null
                          ? Colors.black
                          : Colors.grey,
                    ),
                  ),
                  title: const Text(
                    'Personal',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  trailing: currentGroupId == null
                      ? const Icon(
                          Icons.check_rounded,
                          color: AppColors.primaryCyan,
                        )
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    unawaited(
                      ref.read(groupsProvider.notifier).switchScope(null),
                    );
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
                    title: Text(
                      g.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: isCurrent
                        ? const Icon(
                            Icons.check_rounded,
                            color: AppColors.primaryViolet,
                          )
                        : null,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(
                        ref.read(groupsProvider.notifier).switchScope(g.id),
                      );
                    },
                  );
                }),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      goTab(context, AppRoutes.profile);
                    },
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    label: const Text('Manage Groups in Profile'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final profile = ref.watch(userProfileProvider);
    final resolvedDisplayName =
        (profile != null && profile.displayName.trim().isNotEmpty)
        ? profile.displayName
        : (authState.user?.userMetadata?['full_name'] as String? ??
              authState.user?.email?.split('@').first ??
              'User');
    final group = ref.watch(activeGroupProvider);
    final String currency =
        group?.currency ?? ref.watch(preferredCurrencyProvider);
    final currentUserId = ref.watch(currentUserIdProvider);

    // Totals come from the server (last 30 local days of the active
    // scope), never from the partially loaded list.
    final insightsKey = ref.watch(
      activeInsightsKeyProvider(InsightTimeframe.month),
    );
    final insightsAsync = insightsKey == null
        ? const AsyncLoading<ExpenseInsights>()
        : ref.watch(insightsProvider(insightsKey));
    final insight =
        insightsAsync.value ??
        ExpenseInsights.empty(
          scope: InsightScope.personal,
          timeframe: InsightTimeframe.month,
          currency: currency,
        );

    // One scope for everything on this screen: the active group's
    // expenses, or the user's own spending in personal mode.
    final listKey = ref.watch(dashboardExpenseKeyProvider);
    final listAsync = listKey == null
        ? const AsyncLoading<ExpenseListState>()
        : ref.watch(expenseListProvider(listKey));
    final recentExpenses =
        listAsync.value?.items.take(5).toList() ?? const <Expense>[];
    // Only once the list loaded (not while it loads or after a failure).
    final hasNoExpenses =
        listAsync.hasValue &&
        !listAsync.isLoading &&
        !listAsync.hasError &&
        listAsync.requireValue.items.isEmpty;
    final inGroup = group != null && group.canRead;
    final insightPending = insightsAsync.value == null;
    final scopeLabel = inGroup ? 'GROUP TOTAL' : 'YOUR SPENDING';
    final scopeDescription = inGroup
        ? 'Everything spent in ${group.name} in the last 30 days'
        : 'Your personal expenses plus your share of group expenses, '
              'last 30 days';
    final myBalance = !inGroup
        ? null
        : ref
              .watch(groupBalancesProvider(group.id))
              .value
              ?.where((b) => b.userId == currentUserId)
              .firstOrNull;
    final myGroup = group;
    bool canEdit(Expense expense) => expense.canEdit(
      currentUserId,
      canAddToGroup:
          myGroup != null &&
          expense.groupId == myGroup.id &&
          myGroup.canAddExpenses,
    );

    final suggestions = group == null || !group.canRead
        ? const <SettleSuggestion>[]
        : ref.watch(settleSuggestionsProvider(group.id)).value ??
              const <SettleSuggestion>[];
    final members = ref.watch(activeGroupMembersProvider).value ?? const [];
    String nameOf(String userId) {
      for (final m in members) {
        if (m.userId == userId) return m.label;
      }
      return 'Member';
    }

    Future<void> refreshAll() async {
      if (insightsKey != null) ref.invalidate(insightsProvider(insightsKey));
      if (group != null) {
        ref.invalidate(settleSuggestionsProvider(group.id));
        ref.invalidate(groupBalancesProvider(group.id));
      }
      if (listKey != null) {
        await ref.read(expenseListProvider(listKey).notifier).reload();
      }
    }

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
              onRefresh: refreshAll,
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getGreeting(),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppColors.darkTextTertiary
                                      : AppColors.lightTextTertiary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                resolvedDisplayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  color: isDark
                                      ? AppColors.darkTextPrimary
                                      : AppColors.lightTextPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Group badge or avatar
                        Flexible(
                          child: GestureDetector(
                            onTap: () => _showGroupSwitcher(context, ref),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.darkCardElevated
                                    : AppColors.lightCardElevated,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: group != null
                                      ? AppColors.primaryViolet
                                      : AppColors.primaryCyan,
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    group != null
                                        ? Icons.groups_rounded
                                        : Icons.person_rounded,
                                    size: 16,
                                    color: group != null
                                        ? AppColors.primaryViolet
                                        : AppColors.primaryCyan,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      group != null ? group.name : 'Personal',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: group != null
                                            ? AppColors.primaryViolet
                                            : AppColors.primaryCyan,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ).animate().fadeIn(duration: 300.ms),

                    // First-run tip while the user has no expenses yet
                    // (hidden for good once dismissed).
                    if (hasNoExpenses) ...[
                      const SizedBox(height: 16),
                      FirstExpenseNudge(
                        key: const Key('dashboard-first-expense'),
                        onAddExpense: () {
                          AppHaptics.selection();
                          unawaited(
                            AddEditExpenseSheet.show(context, listKey: listKey),
                          );
                        },
                      ),
                    ],

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
                              Text(
                                scopeLabel,
                                key: const Key('dashboard-scope'),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.8,
                                  color: AppColors.primaryCyan,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryCyan.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  insight.currency,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primaryCyan,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            scopeDescription,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.darkTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                                insightPending
                                    ? '—'
                                    : MoneyFormat.format(insight.total),
                                key: const Key('dashboard-total'),
                                style: const TextStyle(
                                  fontSize: 38,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1,
                                  color: Colors.white,
                                ),
                              )
                              .animate()
                              .fadeIn(delay: 150.ms)
                              .slideX(begin: -0.1, end: 0),
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
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: AppColors.primaryCyan,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Flexible(
                                          child: Text(
                                            'Daily average',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      MoneyFormat.format(insight.averageDaily),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 32,
                                color: Colors.white12,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: AppColors.primaryViolet,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Flexible(
                                          child: Text(
                                            'Expenses',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${insight.count}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (insight.otherCurrencyTotals.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Also spent: '
                              '${insight.otherCurrencyTotals.map(MoneyFormat.format).join(', ')}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.darkTextSecondary,
                              ),
                            ),
                          ],
                          if (myBalance != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              myBalance.net.isPositive
                                  ? 'Your balance: you are owed '
                                        '${MoneyFormat.format(myBalance.net)}'
                                  : myBalance.net.isNegative
                                  ? 'Your balance: you owe '
                                        '${MoneyFormat.format(myBalance.net.abs())}'
                                  : 'Your balance: settled up',
                              key: const Key('dashboard-my-balance'),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.darkTextPrimary,
                              ),
                            ),
                          ],
                          if (insightsAsync.hasError &&
                              !insightsAsync.isLoading) ...[
                            const SizedBox(height: 8),
                            FailureRetry(
                              error: insightsAsync.error!,
                              compact: true,
                              onRetry: () => unawaited(refreshAll()),
                            ),
                          ],
                        ],
                      ),
                    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0),

                    const SizedBox(height: 18),

                    // The FAB adds expenses; this opens the assistant.
                    GestureDetector(
                      onTap: () {
                        AppHaptics.selection();
                        goTab(context, AppRoutes.chat);
                      },
                      child: const GlassCard(
                        borderRadius: 18,
                        padding: EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 16,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 20,
                              color: AppColors.primaryViolet,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Ask the AI Advisor',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ).animate().fadeIn(delay: 250.ms),

                    if (group != null && suggestions.isNotEmpty) ...[
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
                                  onTap: () =>
                                      goTab(context, AppRoutes.profile),
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
                            ...suggestions.take(2).map((d) {
                              final iOwe = d.fromUser == currentUserId;
                              final owedToMe = d.toUser == currentUserId;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      iOwe
                                          ? Icons.arrow_circle_up_rounded
                                          : (owedToMe
                                                ? Icons
                                                      .arrow_circle_down_rounded
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
                                            ? 'You owe ${nameOf(d.toUser)}'
                                            : (owedToMe
                                                  ? '${nameOf(d.fromUser)} owes you'
                                                  : '${nameOf(d.fromUser)} owes ${nameOf(d.toUser)}'),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      MoneyFormat.format(d.amount),
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
                        Expanded(
                          child: Text(
                            'Highlights',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.lightTextPrimary,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => goTab(context, AppRoutes.insights),
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
                                const Icon(
                                  Icons.speed_rounded,
                                  color: AppColors.primaryEmerald,
                                  size: 22,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Daily Average',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? AppColors.darkTextTertiary
                                        : AppColors.lightTextTertiary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  MoneyFormat.format(insight.averageDaily),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
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
                                const Icon(
                                  Icons.pie_chart_outline_rounded,
                                  color: AppColors.primaryAmber,
                                  size: 22,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Top Category',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? AppColors.darkTextTertiary
                                        : AppColors.lightTextTertiary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  insight.topCategory?.category ?? 'None',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
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
                        Expanded(
                          child: Text(
                            inGroup
                                ? 'Recent group expenses'
                                : 'Recent expenses',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.lightTextPrimary,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => goTab(context, AppRoutes.expenses),
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

                    if (listAsync.hasError && recentExpenses.isEmpty) ...[
                      GlassCard(
                        borderRadius: 20,
                        padding: const EdgeInsets.all(8),
                        child: FailureRetry(
                          error: listAsync.error!,
                          onRetry: () => unawaited(refreshAll()),
                        ),
                      ),
                    ] else if (listAsync.isLoading &&
                        recentExpenses.isEmpty) ...[
                      const GlassCard(
                        borderRadius: 20,
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ] else if (recentExpenses.isEmpty) ...[
                      GlassCard(
                        borderRadius: 20,
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          key: const Key('dashboard-empty'),
                          child: Column(
                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                size: 36,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                inGroup
                                    ? 'No group expenses yet.'
                                    : 'No expenses yet. Tap + to record '
                                          'your first one.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      ...recentExpenses.map((expense) {
                        final catColor = AppColors.getCategoryColor(
                          expense.category,
                        );
                        final catIcon = AppConstants.getCategoryIcon(
                          expense.category,
                        );

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassCard(
                            borderRadius: 18,
                            padding: const EdgeInsets.all(14),
                            onTap: canEdit(expense)
                                ? () {
                                    AppHaptics.selection();
                                    unawaited(
                                      AddEditExpenseSheet.show(
                                        context,
                                        expense: expense,
                                        listKey: listKey,
                                      ),
                                    );
                                  }
                                : null,
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: catColor.withValues(alpha: 0.16),
                                  ),
                                  child: Icon(
                                    catIcon,
                                    color: catColor,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        expense.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${expense.category} • ${DateHelpers.formatTime(expense.spentAt)} • ${DateHelpers.formatRelative(expense.spentAt)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? AppColors.darkTextTertiary
                                              : AppColors.lightTextTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  MoneyFormat.format(expense.amount),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
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
        tooltip: 'Add expense',
        onPressed: () {
          AppHaptics.selection();
          unawaited(AddEditExpenseSheet.show(context, listKey: listKey));
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 4,
        child: const Icon(Icons.add_rounded, size: 28),
      ).animate().scale(delay: 400.ms, curve: Curves.easeOutBack),
    );
  }
}
