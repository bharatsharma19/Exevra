import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/storage/preferences.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/insights.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/expense_provider.dart';
import '../../../providers/groups_provider.dart';
import '../../../providers/insights_provider.dart';
import '../../dashboard/widgets/inline_failure.dart';
import '../../expenses/screens/add_edit_expense_sheet.dart';
import '../insights_chart_data.dart';
import '../insights_labels.dart';
import '../insights_timeframe_memory.dart';
import '../widgets/biggest_expense_card.dart';
import '../widgets/category_breakdown.dart';
import '../widgets/insights_skeleton.dart';
import '../widgets/insights_summary_card.dart';
import '../widgets/spending_trend_chart.dart';

/// Insights: what was spent in the active scope (personal or the active
/// group) over the last week, month or year, by day or month and by
/// category. Totals come from the server, in one currency; other
/// currencies are listed separately.
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  bool _restoreChecked = false;

  /// The time range to show. The first build restores the range this user
  /// last picked on this device, so it is fetched right away instead of
  /// after a default month.
  InsightTimeframe _timeframe() {
    final current = ref.watch(insightsTimeframeProvider);
    if (_restoreChecked) return current;
    _restoreChecked = true;
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return current;
    InsightTimeframe? saved;
    try {
      saved = InsightsTimeframeMemory.read(
        ref.read(sharedPreferencesProvider),
        userId,
      );
    } on Object {
      saved = null;
    }
    if (saved == null || saved == current) return current;
    final restored = saved;
    // Providers cannot change while the tree builds.
    unawaited(
      Future.microtask(() {
        if (mounted) ref.read(insightsTimeframeProvider.notifier).set(restored);
      }),
    );
    return restored;
  }

  void _select(InsightTimeframe value) {
    if (value == ref.read(insightsTimeframeProvider)) return;
    AppHaptics.selection();
    ref.read(insightsTimeframeProvider.notifier).set(value);
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    try {
      unawaited(
        InsightsTimeframeMemory.save(
          ref.read(sharedPreferencesProvider),
          userId,
          value,
        ),
      );
    } on Object {
      // No preferences (tests, early start): the range is not remembered.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    final timeframe = _timeframe();
    final key = ref.watch(activeInsightsKeyProvider(timeframe));
    final async = key == null
        ? const AsyncLoading<ExpenseInsights>()
        : ref.watch(insightsProvider(key));
    final group = ref.watch(activeGroupProvider);
    final inGroup = key?.scope == InsightScope.group;
    final canAdd = !inGroup || (group?.canAddExpenses ?? false);
    final period = timeframePeriod(l10n, timeframe);
    final data = async.value;

    Future<void> reload() async {
      if (key == null) return;
      ref.invalidate(insightsProvider(key));
      try {
        await ref.read(insightsProvider(key).future);
      } on Object {
        // Shown by the error state.
      }
    }

    void addExpense() {
      AppHaptics.selection();
      unawaited(
        AddEditExpenseSheet.show(
          context,
          listKey: ref.read(dashboardExpenseKeyProvider),
        ),
      );
    }

    Widget section(String title, Widget child) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: title,
          padding: const EdgeInsetsDirectional.only(
            top: AppSpacing.xl,
            bottom: AppSpacing.sm,
          ),
        ),
        child,
      ],
    );

    final List<Widget> content;
    if (data == null && async.hasError) {
      final error = async.error;
      content = [
        AppCard(
          key: const Key('insights-error'),
          child: ErrorState(
            title: l10n.insightsErrorTitle,
            message: friendlyMessage(
              error is AppFailure ? error : const AppFailure.unknown(),
            ),
            onRetry: () => unawaited(reload()),
          ),
        ),
      ];
    } else if (data == null) {
      content = const [InsightsSkeleton()];
    } else {
      content = [
        if (async.hasError && !async.isLoading) ...[
          InlineFailure(
            error: async.error!,
            onRetry: () => unawaited(reload()),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        InsightsSummaryCard(insights: data, period: period),
        if (data.isEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            key: const Key('insights-empty'),
            child: EmptyState(
              icon: Icons.insights_rounded,
              title: l10n.insightsEmptyTitle,
              message: inGroup
                  ? l10n.insightsEmptyGroup
                  : l10n.insightsEmptyPersonal,
              actionLabel: canAdd ? l10n.insightsAddExpense : null,
              onAction: canAdd ? addExpense : null,
            ),
          ),
        ] else ...[
          section(
            l10n.insightsTrendTitle,
            SpendingTrendChart(
              buckets: zeroFilledBuckets(data, today: DateTime.now()),
              timeframe: data.timeframe,
              currency: data.currency,
              period: period,
            ),
          ),
          if (data.categories.isNotEmpty)
            section(
              l10n.insightsCategoriesTitle,
              CategoryBreakdown(categories: data.categories),
            ),
          if (data.highest != null)
            section(
              l10n.insightsBiggestExpense,
              BiggestExpenseCard(expense: data.highest!),
            ),
        ],
      ];
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.insightsTitle),
        actions: [
          AppIconButton(
            icon: Icons.refresh_rounded,
            tooltip: l10n.insightsRefreshTooltip,
            onPressed: key == null
                ? null
                : () {
                    AppHaptics.light();
                    unawaited(reload());
                  },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            key: const Key('insights-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.sm,
              AppSpacing.gutter,
              AppSpacing.xxxl,
            ),
            children: [
              Semantics(
                label: l10n.insightsTimeframeLabel,
                container: true,
                child: SegmentedButton<InsightTimeframe>(
                  key: const Key('insights-timeframe'),
                  showSelectedIcon: false,
                  segments: [
                    for (final t in InsightTimeframe.values)
                      ButtonSegment(
                        value: t,
                        label: Text(
                          timeframeName(l10n, t),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  selected: {timeframe},
                  onSelectionChanged: (s) => _select(s.first),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                inGroup
                    ? l10n.insightsScopeGroup(
                        group?.name ?? l10n.insightsScopeGroupFallback,
                      )
                    : l10n.insightsScopePersonal,
                key: const Key('insights-scope'),
                style: textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ...content,
            ],
          ),
        ),
      ),
    );
  }
}
