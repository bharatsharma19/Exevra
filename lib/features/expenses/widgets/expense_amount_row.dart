import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../models/currency_info.dart';
import 'inline_notice.dart';
import 'money_input_field.dart';

/// The expense amount with its currency: a picker for personal expenses,
/// or the group's fixed currency with a lock for group expenses.
class ExpenseAmountRow extends StatelessWidget {
  /// Creates the row.
  const ExpenseAmountRow({
    required this.controller,
    required this.currency,
    required this.currencyFixed,
    required this.enabled,
    required this.onCurrencyChanged,
    this.lockedMessage,
    this.warning,
    super.key,
  });

  /// Why the amount is locked, shown with a lock under the row.
  final String? lockedMessage;

  /// Something to check before saving (the currency changed).
  final String? warning;

  /// Amount text.
  final TextEditingController controller;

  /// Currency of the amount.
  final String currency;

  /// Whether the currency is the group's and cannot be picked.
  final bool currencyFixed;

  /// Whether the amount can change (false when the expense is locked).
  final bool enabled;

  /// Called with a newly picked personal currency.
  final ValueChanged<String> onCurrencyChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final Widget currencyControl;
    if (currencyFixed) {
      currencyControl = Tooltip(
        message: l10n.expensesGroupCurrencyTooltip(currency),
        child: Semantics(
          label: l10n.expensesGroupCurrencyTooltip(currency),
          excludeSemantics: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSizes.minTapTarget),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: AppSizes.iconSm,
                  color: palette.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  currency,
                  key: const Key('expense-currency-locked'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      currencyControl = Semantics(
        label: l10n.expensesCurrencyLabel,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const Key('expense-currency'),
            value: currency,
            borderRadius: AppRadius.mdAll,
            items: [
              for (final c in CurrencyInfo.all)
                DropdownMenuItem(value: c.code, child: Text(c.code)),
            ],
            onChanged: (value) {
              if (value != null) onCurrencyChanged(value);
            },
          ),
        ),
      );
    }
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: MoneyInputField(
            key: const Key('expense-amount'),
            controller: controller,
            currency: currency,
            label: l10n.expensesAmountLabel,
            enabled: enabled,
            large: true,
            textInputAction: TextInputAction.next,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: currencyControl,
        ),
      ],
    );
    final locked = lockedMessage;
    final warning = this.warning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        if (locked != null) ...[
          const SizedBox(height: AppSpacing.sm),
          InlineNotice(
            key: const Key('expense-locked'),
            kind: NoticeKind.locked,
            message: locked,
          ),
        ],
        if (warning != null) ...[
          const SizedBox(height: AppSpacing.sm),
          InlineNotice(kind: NoticeKind.warning, message: warning),
        ],
      ],
    );
  }
}
