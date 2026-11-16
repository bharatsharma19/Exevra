import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/insights.dart';
import '../../../models/money.dart';
import 'inline_failure.dart';

/// The home screen's hero: what was spent in the scope and period, from
/// the server summary (never from the partly loaded list).
///
/// [title] says whose spending it is ("Your spending" or "Group total") and
/// [note] spells out what is included, so the personal figure (which
/// includes the user's share of group expenses) and a group's total are
/// never confused.
class SpendingSummaryCard extends StatelessWidget {
  const SpendingSummaryCard({
    required this.title,
    required this.period,
    required this.note,
    required this.insights,
    required this.loading,
    required this.onRetry,
    this.error,
    this.balance,
    super.key,
  });

  final String title;
  final String period;
  final String note;

  /// The loaded summary, or null while it loads or after it failed.
  final ExpenseInsights? insights;

  /// A first load is in flight (shows placeholders).
  final bool loading;

  /// The latest load failed.
  final Object? error;
  final VoidCallback onRetry;

  /// The user's net balance in the active group (group view only).
  final Money? balance;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final data = insights;
    final showSkeleton = data == null && loading && error == null;

    final totalText = data == null ? '—' : MoneyFormat.format(data.total);
    return AppCard.glass(
      key: const Key('dashboard-summary'),
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
                title,
                key: const Key('dashboard-scope'),
                style: textTheme.titleSmall?.copyWith(
                  color: palette.textPrimary,
                ),
              ),
              _Pill(text: period),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            note,
            style: textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          if (showSkeleton)
            Semantics(
              label: l10n.loading,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 180, height: 40),
                  SizedBox(height: AppSpacing.lg),
                  SkeletonBox(width: 220, height: 16),
                ],
              ),
            )
          else ...[
            AmountText(
              totalText,
              key: const Key('dashboard-total'),
              scaleDown: true,
              semanticLabel: l10n.dashboardSummaryLabel(
                title,
                period,
                data == null ? l10n.dashboardTotalUnavailable : totalText,
              ),
              style: textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            if (data != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Divider(height: 1, color: palette.outlineVariant),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xl,
                runSpacing: AppSpacing.md,
                children: [
                  _Metric(
                    icon: Icons.calendar_today_rounded,
                    label: l10n.dashboardDailyAverage,
                    value: MoneyFormat.format(data.averageDaily),
                  ),
                  _Metric(
                    icon: Icons.receipt_long_rounded,
                    label: l10n.dashboardExpenseCountLabel,
                    value: NumberFormat.decimalPattern().format(data.count),
                  ),
                ],
              ),
              if (data.otherCurrencyTotals.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.dashboardOtherCurrencies(
                    data.otherCurrencyTotals.map(MoneyFormat.format).join(', '),
                  ),
                  key: const Key('dashboard-other-currencies'),
                  style: textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ],
          ],
          if (balance != null) ...[
            const SizedBox(height: AppSpacing.md),
            _BalanceLine(net: balance!),
          ],
          if (error != null && !loading) ...[
            const SizedBox(height: AppSpacing.sm),
            InlineFailure(error: error!, onRetry: onRetry),
          ],
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

/// "You owe ₹250" / "The group owes you ₹250" / "You're all settled up",
/// with an arrow icon so the direction never depends on colour.
class _BalanceLine extends StatelessWidget {
  const _BalanceLine({required this.net});

  final Money net;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final (IconData icon, Color color, String text) = net.isNegative
        ? (
            Icons.arrow_circle_up_rounded,
            palette.negativeAmount,
            l10n.dashboardBalanceYouOwe(MoneyFormat.format(net.abs())),
          )
        : net.isPositive
        ? (
            Icons.arrow_circle_down_rounded,
            palette.positiveAmount,
            l10n.dashboardBalanceOwesYou(MoneyFormat.format(net)),
          )
        : (
            Icons.check_circle_outline_rounded,
            palette.success,
            l10n.dashboardBalanceSettled,
          );
    return MergeSemantics(
      child: Row(
        key: const Key('dashboard-my-balance'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, color: color)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.dashboardBalanceTitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                Text(text, style: textTheme.titleSmall?.copyWith(color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
