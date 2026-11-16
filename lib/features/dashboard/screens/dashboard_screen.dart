import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/accessibility/reduce_motion.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/router/navigation.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/system_ui.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/balance.dart';
import '../../../models/expense.dart';
import '../../../models/insights.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/expense_provider.dart';
import '../../../providers/group_detail_providers.dart';
import '../../../providers/groups_provider.dart';
import '../../../providers/insights_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../expenses/screens/add_edit_expense_sheet.dart';
import '../../insights/insights_labels.dart';
import '../../onboarding/first_expense_nudge.dart';
import '../../onboarding/onboarding_store.dart';
import '../widgets/dashboard_cards.dart';
import '../widgets/dashboard_header.dart';
import '../widgets/recent_expenses_section.dart';
import '../widgets/scope_switcher_sheet.dart';
import '../widgets/spending_summary_card.dart';

/// The one period every figure on the home screen covers. The summary,
/// its label and the highlights all read it, so they always agree.
const InsightTimeframe dashboardTimeframe = InsightTimeframe.month;

/// How many expenses the recent list shows.
const int dashboardRecentCount = 5;

/// Home: the spending summary of the active scope (personal or the active
/// group), highlights and the newest expenses of the same scope.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final palette = context.palette;

    final authUser = ref.watch(authControllerProvider).user;
    final profile = ref.watch(userProfileProvider);
    final displayName =
        (profile != null && profile.displayName.trim().isNotEmpty)
        ? profile.displayName
        : (authUser?.userMetadata?['full_name'] as String? ??
              authUser?.email?.split('@').first ??
              '');
    final group = ref.watch(activeGroupProvider);
    final inGroup = group != null && group.canRead;
    final currentUserId = ref.watch(currentUserIdProvider);

    // Totals come from the server for the whole period of the active
    // scope, never from the partially loaded list.
    final insightsKey = ref.watch(
      activeInsightsKeyProvider(dashboardTimeframe),
    );
    final insightsAsync = insightsKey == null
        ? const AsyncLoading<ExpenseInsights>()
        : ref.watch(insightsProvider(insightsKey));

    // The list uses the same scope as the summary: the active group's
    // expenses, or the user's own personal expenses.
    final listKey = ref.watch(dashboardExpenseKeyProvider);
    final listAsync = listKey == null
        ? const AsyncLoading<ExpenseListState>()
        : ref.watch(expenseListProvider(listKey));
    final recent =
        listAsync.value?.items.take(dashboardRecentCount).toList() ??
        const <Expense>[];
    // Only once the list loaded (not while it loads or after a failure).
    final hasNoExpenses =
        listAsync.hasValue &&
        !listAsync.isLoading &&
        !listAsync.hasError &&
        listAsync.requireValue.items.isEmpty;
    // The first-expense tip is only for the personal list.
    final nudgeDismissed =
        ref.watch(firstExpenseNudgeDismissedProvider).value ?? true;
    final showNudge = hasNoExpenses && !inGroup;
    final nudgeOffersAdd = showNudge && !nudgeDismissed;

    final balance = !inGroup
        ? null
        : ref
              .watch(groupBalancesProvider(group.id))
              .value
              ?.where((b) => b.userId == currentUserId)
              .firstOrNull
              ?.net;
    final List<SettleSuggestion> suggestions = !inGroup
        ? const []
        : ref.watch(settleSuggestionsProvider(group.id)).value ?? const [];
    final members = ref.watch(activeGroupMembersProvider).value ?? const [];
    String nameOf(String userId) {
      for (final m in members) {
        if (m.userId == userId) return m.label;
      }
      return l10n.dashboardMemberFallback;
    }

    bool canEdit(Expense expense) => expense.canEdit(
      currentUserId,
      canAddToGroup:
          group != null && expense.groupId == group.id && group.canAddExpenses,
    );
    final canAdd = !inGroup || group.canAddExpenses;

    void addExpense() {
      AppHaptics.selection();
      unawaited(AddEditExpenseSheet.show(context, listKey: listKey));
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

    final period = timeframePeriod(l10n, dashboardTimeframe);
    final reduceMotion = context.reduceMotion;
    Widget entrance(Widget child, int order) => reduceMotion
        ? child
        : child
              .animate()
              .fadeIn(delay: (60 * order).ms, duration: AppDurations.medium)
              .slideY(begin: 0.04, end: 0);

    final children = <Widget>[
      DashboardHeader(
        displayName: displayName,
        scopeName: inGroup ? group.name : l10n.dashboardScopePersonal,
        inGroup: inGroup,
        onChangeScope: () => unawaited(showScopeSwitcher(context, ref)),
      ),
      if (showNudge) ...[
        const SizedBox(height: AppSpacing.lg),
        FirstExpenseNudge(
          key: const Key('dashboard-first-expense'),
          onAddExpense: addExpense,
        ),
      ],
      const SizedBox(height: AppSpacing.lg),
      entrance(
        SpendingSummaryCard(
          title: inGroup
              ? l10n.dashboardGroupTotal
              : l10n.dashboardYourSpending,
          period: period,
          note: inGroup
              ? l10n.dashboardGroupScopeNote(group.name)
              : l10n.dashboardPersonalScopeNote,
          insights: insightsAsync.value,
          loading: insightsAsync.isLoading,
          error: insightsAsync.hasError ? insightsAsync.error : null,
          balance: balance,
          onRetry: () => unawaited(refreshAll()),
        ),
        1,
      ),
      if (suggestions.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
        SettleUpCard(
          suggestions: suggestions,
          currentUserId: currentUserId,
          nameOf: nameOf,
          onSettleUp: () => goTab(context, AppRoutes.profile),
        ),
      ],
      const SizedBox(height: AppSpacing.lg),
      entrance(
        AssistantEntryCard(
          onTap: () {
            AppHaptics.selection();
            goTab(context, AppRoutes.chat);
          },
        ),
        2,
      ),
      const SizedBox(height: AppSpacing.md),
      SectionHeader(
        title: l10n.dashboardHighlightsTitle,
        actionLabel: l10n.dashboardSeeInsights,
        onAction: () => goTab(context, AppRoutes.insights),
        padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.xs),
      ),
      HighlightsRow(
        insights: insightsAsync.value,
        loading: insightsAsync.isLoading,
        failed: insightsAsync.hasError,
      ),
      const SizedBox(height: AppSpacing.md),
      RecentExpensesSection(
        title: inGroup
            ? l10n.dashboardRecentGroup(group.name)
            : l10n.dashboardRecentPersonal,
        expenses: recent,
        loading: listAsync.isLoading,
        error: listAsync.hasError ? listAsync.error : null,
        emptyTitle: inGroup
            ? l10n.dashboardEmptyGroupTitle
            : l10n.dashboardEmptyPersonalTitle,
        emptyMessage: inGroup
            ? l10n.dashboardEmptyGroupMessage(group.name)
            : l10n.dashboardEmptyPersonalMessage,
        onAdd: canAdd && !nudgeOffersAdd ? addExpense : null,
        onSeeAll: () => goTab(context, AppRoutes.expenses),
        onRetry: () => unawaited(refreshAll()),
        canEdit: canEdit,
        onOpen: (expense) {
          AppHaptics.selection();
          unawaited(
            AddEditExpenseSheet.show(
              context,
              expense: expense,
              listKey: listKey,
            ),
          );
        },
      ),
    ];

    // No app bar here, so the region keeps the bar icons readable on the
    // accent wash and follows theme changes.
    return SystemUiRegion(
      child: Scaffold(
        body: DecoratedBox(
          // A soft accent wash at the top gives the frosted summary card
          // something to blur; text sits on cards or the plain background.
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.35],
              colors: [
                palette.accentContainer.withValues(alpha: 0.55),
                palette.background,
              ],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: refreshAll,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.lg,
                  AppSpacing.gutter,
                  // Room for the floating button over the last row.
                  96,
                ),
                children: children,
              ),
            ),
          ),
        ),
        floatingActionButton: canAdd
            ? FloatingActionButton(
                // Every tab stays alive in one page route: a shared default
                // hero tag breaks the transition to sign-in.
                heroTag: null,
                tooltip: l10n.dashboardAddExpense,
                onPressed: addExpense,
                child: const Icon(Icons.add_rounded),
              )
            : null,
      ),
    );
  }
}
