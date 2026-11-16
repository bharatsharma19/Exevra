import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/accessibility/reduce_motion.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/insights.dart';
import '../../dashboard/widgets/category_avatar.dart';

/// Spending by category: a donut (decorative, no text on the slices) and a
/// legend that spells out every category with its icon, amount, share and
/// number of expenses, so nothing depends on telling colours apart.
class CategoryBreakdown extends StatelessWidget {
  const CategoryBreakdown({required this.categories, super.key});

  /// Largest first.
  final List<CategoryTotal> categories;

  static String _percent(double share) =>
      NumberFormat.percentPattern().format(share);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final details = categories
        .map((c) => '${c.category} ${_percent(c.share)}')
        .join(', ');
    return AppCard(
      key: const Key('insights-categories'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: l10n.insightsCategoriesSummary(details),
            child: ExcludeSemantics(
              child: SizedBox(
                height: 180,
                child: PieChart(
                  duration: context.reduceMotion
                      ? Duration.zero
                      : AppDurations.medium,
                  PieChartData(
                    pieTouchData: PieTouchData(enabled: false),
                    borderData: FlBorderData(show: false),
                    sectionsSpace: 2,
                    centerSpaceRadius: 52,
                    sections: [
                      for (final c in categories)
                        PieChartSectionData(
                          color: palette.categoryColor(c.category),
                          value: c.total.amountMinor.toDouble(),
                          radius: 30,
                          showTitle: false,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final c in categories) _CategoryRow(category: c),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category});

  final CategoryTotal category;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final amount = MoneyFormat.format(category.total);
    final percent = CategoryBreakdown._percent(category.share);
    final count = l10n.insightsExpenseCount(category.count);
    return Semantics(
      container: true,
      label: l10n.insightsCategoryRowLabel(
        category.category,
        amount,
        percent,
        count,
      ),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              CategoryAvatar(category: category.category, size: 36),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.category,
                      style: textTheme.titleSmall?.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    Text(
                      '$percent · $count',
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ClipRRect(
                      borderRadius: AppRadius.pillAll,
                      child: LinearProgressIndicator(
                        value: category.share.clamp(0, 1),
                        minHeight: 4,
                        color: palette.categoryColor(category.category),
                        backgroundColor: palette.surfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Flexible(
                flex: 2,
                child: Text(
                  amount,
                  textAlign: TextAlign.end,
                  style: textTheme.titleSmall?.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
