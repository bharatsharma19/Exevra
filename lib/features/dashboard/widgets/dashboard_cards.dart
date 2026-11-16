import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/balance.dart';
import '../../../models/insights.dart';
import 'category_avatar.dart';

/// Opens the assistant tab. Adding expenses is on the floating button.
class AssistantEntryCard extends StatelessWidget {
  const AssistantEntryCard({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      key: const Key('dashboard-assistant'),
      onTap: onTap,
      child: Row(
        children: [
          ExcludeSemantics(
            child: CircleAvatar(
              backgroundColor: palette.secondaryContainer,
              child: Icon(
                Icons.auto_awesome_rounded,
                color: palette.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.dashboardAskAssistant,
                  style: textTheme.titleSmall?.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
                Text(
                  l10n.dashboardAskAssistantSubtitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          ExcludeSemantics(
            child: Icon(
              Icons.chevron_right_rounded,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The group's suggested payments ("You owe Priya ₹250"), at most two,
/// with a link to settle up.
class SettleUpCard extends StatelessWidget {
  const SettleUpCard({
    required this.suggestions,
    required this.currentUserId,
    required this.nameOf,
    required this.onSettleUp,
    super.key,
  });

  final List<SettleSuggestion> suggestions;
  final String? currentUserId;
  final String Function(String userId) nameOf;
  final VoidCallback onSettleUp;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    return AppCard(
      key: const Key('dashboard-settle-up'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: l10n.dashboardSettleUpTitle,
            actionLabel: l10n.dashboardSettleUpAction,
            onAction: onSettleUp,
            padding: const EdgeInsetsDirectional.only(
              start: AppSpacing.lg,
              end: AppSpacing.sm,
            ),
          ),
          for (final d in suggestions.take(2))
            Builder(
              builder: (context) {
                final iOwe = d.fromUser == currentUserId;
                final owedToMe = d.toUser == currentUserId;
                final (IconData icon, Color color, String text) = iOwe
                    ? (
                        Icons.arrow_circle_up_rounded,
                        palette.negativeAmount,
                        l10n.dashboardYouOwePerson(nameOf(d.toUser)),
                      )
                    : owedToMe
                    ? (
                        Icons.arrow_circle_down_rounded,
                        palette.positiveAmount,
                        l10n.dashboardPersonOwesYou(nameOf(d.fromUser)),
                      )
                    : (
                        Icons.swap_horiz_rounded,
                        palette.textSecondary,
                        l10n.dashboardPersonOwesPerson(
                          nameOf(d.fromUser),
                          nameOf(d.toUser),
                        ),
                      );
                return AppListTile(
                  leading: ExcludeSemantics(child: Icon(icon, color: color)),
                  title: text,
                  trailing: AmountText(
                    MoneyFormat.format(d.amount),
                    sign: iOwe
                        ? AmountSign.negative
                        : owedToMe
                        ? AmountSign.positive
                        : AmountSign.neutral,
                    showSign: false,
                    semanticLabel: MoneyFormat.format(d.amount),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Top category and the biggest expense of the period.
class HighlightsRow extends StatelessWidget {
  const HighlightsRow({
    required this.insights,
    this.loading = false,
    this.failed = false,
    super.key,
  });

  final ExpenseInsights? insights;

  /// Insights are on their way: placeholders instead of "None yet".
  final bool loading;

  /// Insights failed to load: a short inline error instead of "None yet"
  /// (the summary card above offers Retry).
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final data = insights;
    final state = data != null
        ? _HighlightState.ready
        : failed
        ? _HighlightState.failed
        : loading
        ? _HighlightState.loading
        : _HighlightState.ready;
    final top = data?.topCategory;
    final biggest = data?.highest;
    final cards = [
      _HighlightCard(
        key: const Key('dashboard-top-category'),
        state: state,
        label: l10n.dashboardTopCategory,
        leading: top == null
            ? const _IconBadge(icon: Icons.pie_chart_outline_rounded)
            : CategoryAvatar(category: top.category),
        value: top?.category ?? l10n.dashboardNoneYet,
        detail: top == null ? null : MoneyFormat.format(top.total),
      ),
      _HighlightCard(
        key: const Key('dashboard-biggest'),
        state: state,
        label: l10n.dashboardBiggestExpense,
        leading: biggest == null
            ? const _IconBadge(icon: Icons.arrow_upward_rounded)
            : CategoryAvatar(category: biggest.category),
        value: biggest == null
            ? l10n.dashboardNoneYet
            : MoneyFormat.format(biggest.amount),
        detail: biggest?.title,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 360 ||
            MediaQuery.textScalerOf(context).scale(1) >= 1.5;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cards[0],
              const SizedBox(height: AppSpacing.md),
              cards[1],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: cards[1]),
            ],
          ),
        );
      },
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ExcludeSemantics(
      child: CircleAvatar(
        backgroundColor: palette.surfaceVariant,
        child: Icon(icon, color: palette.textSecondary),
      ),
    );
  }
}

enum _HighlightState { ready, loading, failed }

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.state,
    required this.label,
    required this.leading,
    required this.value,
    this.detail,
    super.key,
  });

  final _HighlightState state;
  final String label;
  final Widget leading;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final labelText = Text(
      label,
      style: textTheme.bodySmall?.copyWith(color: palette.textSecondary),
    );
    final Widget body;
    switch (state) {
      case _HighlightState.loading:
        body = Semantics(
          label: '$label, ${l10n.loading}',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox.circle(size: 40),
              const SizedBox(height: AppSpacing.sm),
              labelText,
              const SizedBox(height: AppSpacing.xs),
              const SkeletonBox(width: 96, height: 18),
            ],
          ),
        );
      case _HighlightState.failed:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _IconBadge(icon: Icons.error_outline_rounded),
            const SizedBox(height: AppSpacing.sm),
            labelText,
            Text(
              l10n.dashboardHighlightFailed,
              key: const Key('dashboard-highlight-failed'),
              style: textTheme.bodyMedium?.copyWith(color: palette.danger),
            ),
          ],
        );
      case _HighlightState.ready:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            leading,
            const SizedBox(height: AppSpacing.sm),
            labelText,
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium?.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (detail != null)
              Text(
                detail!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
          ],
        );
    }
    return AppCard(child: MergeSemantics(child: body));
  }
}
