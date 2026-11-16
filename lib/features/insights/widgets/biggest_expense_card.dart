import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/insights.dart';
import '../../dashboard/widgets/category_avatar.dart';

/// The single largest expense of the period: title, category, date and
/// amount.
class BiggestExpenseCard extends StatelessWidget {
  const BiggestExpenseCard({required this.expense, super.key});

  final InsightExpense expense;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final amount = MoneyFormat.format(expense.amount);
    final date = DateFormat.yMMMd().format(expense.spentAt.toLocal());
    final detail = l10n.insightsExpenseDetail(expense.category, date);
    return AppCard(
      key: const Key('insights-biggest'),
      padding: EdgeInsets.zero,
      child: AppListTile(
        leading: CategoryAvatar(category: expense.category),
        title: expense.title,
        subtitle: detail,
        semanticLabel: '${expense.title}, $detail, $amount',
        trailing: Text(
          amount,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(color: context.palette.textPrimary),
        ),
      ),
    );
  }
}
