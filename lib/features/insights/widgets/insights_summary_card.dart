import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/insights.dart';

/// The insights hero: total spent in the period, the number of expenses,
/// the daily average and the biggest expense. Amounts in other currencies
/// are listed under the total with a note that they are not included.
class InsightsSummaryCard extends StatelessWidget {
  const InsightsSummaryCard({
    required this.insights,
    required this.period,
    super.key,
  });

  final ExpenseInsights insights;

  /// "Last 30 days" and so on.
  final String period;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final total = MoneyFormat.format(insights.total);
    final highest = insights.highest;
    return AppCard.glass(
      key: const Key('insights-summary'),
      padding: const EdgeInsets.all(AppSpacing.xl - 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l10n.insightsTotalSpent,
                style: textTheme.titleSmall?.copyWith(
                  color: palette.textPrimary,
                ),
              ),
              _Pill(text: period),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AmountText(
            total,
            key: const Key('insights-total'),
            scaleDown: true,
            semanticLabel: '${l10n.insightsTotalSpent}, $period: $total',
            style: textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          Text(
            l10n.insightsExpenseCount(insights.count),
            style: textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
          ),
          if (insights.otherCurrencyTotals.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.insightsOtherCurrencies(
                insights.otherCurrencyTotals.map(MoneyFormat.format).join(', '),
              ),
              key: const Key('insights-other-currencies'),
              style: textTheme.bodyMedium?.copyWith(color: palette.textPrimary),
            ),
            Text(
              l10n.insightsOtherCurrenciesNote,
              style: textTheme.bodySmall?.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Divider(height: 1, color: palette.outlineVariant),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.md,
            children: [
              _Metric(
                icon: Icons.calendar_today_rounded,
                label: l10n.insightsDailyAverage,
                value: MoneyFormat.format(insights.averageDaily),
              ),
              _Metric(
                icon: Icons.arrow_upward_rounded,
                label: l10n.insightsBiggestExpense,
                value: highest == null
                    ? l10n.insightsNone
                    : MoneyFormat.format(highest.amount),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.accentContainer,
        borderRadius: AppRadius.pillAll,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: palette.onAccentContainer),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: AppSizes.iconSm, color: palette.accent),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: textTheme.titleSmall?.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
