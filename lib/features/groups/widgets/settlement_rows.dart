import 'package:flutter/material.dart';

import '../../../core/errors/failure_messages.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/date_helpers.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/money.dart';
import '../../../models/settlement.dart';
import '../../expenses/widgets/inline_notice.dart';

/// Names a user id within one group ("You", a member, a former member).
typedef MemberNamer = String Function(String? userId);

/// One member's balance in the group: who owes and who gets money back,
/// in words and with a signed amount, so it never relies on colour alone.
class BalanceRow extends StatelessWidget {
  /// Creates the row.
  const BalanceRow({
    required this.name,
    required this.net,
    required this.isYou,
    super.key,
  });

  /// Display name of the member.
  final String name;

  /// What the group owes them (positive) or they owe (negative).
  final Money net;

  /// Whether this row is the signed-in user.
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final amount = MoneyFormat.format(net.abs());
    final String status;
    final AmountSign sign;
    if (net.isPositive) {
      status = isYou
          ? l10n.settleYouAreOwed(amount)
          : l10n.settleMemberIsOwed(name, amount);
      sign = AmountSign.positive;
    } else if (net.isNegative) {
      status = isYou
          ? l10n.settleYouOwe(amount)
          : l10n.settleMemberOwes(name, amount);
      sign = AmountSign.negative;
    } else {
      status = isYou
          ? l10n.settleYouAreSettled
          : l10n.settleMemberSettled(name);
      sign = AmountSign.neutral;
    }
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            ExcludeSemantics(child: AppAvatar(name: name, radius: 16)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                status,
                style: textTheme.bodyMedium?.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ),
            if (sign != AmountSign.neutral) ...[
              const SizedBox(width: AppSpacing.sm),
              ExcludeSemantics(
                child: AmountText(
                  amount,
                  sign: sign,
                  style: textTheme.titleSmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A settle-up suggestion; the payer gets a Pay button.
class SuggestionRow extends StatelessWidget {
  /// Creates the row.
  const SuggestionRow({
    required this.fromUser,
    required this.toUser,
    required this.amount,
    required this.currentUserId,
    required this.nameOf,
    required this.onPay,
    super.key,
  });

  /// Who should pay.
  final String fromUser;

  /// Who should receive.
  final String toUser;

  /// How much.
  final Money amount;

  /// The signed-in user.
  final String? currentUserId;

  /// Names user ids.
  final MemberNamer nameOf;

  /// Opens the payment form (only offered to the payer).
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final formatted = MoneyFormat.format(amount);
    final iPay = fromUser == currentUserId;
    final iReceive = toUser == currentUserId;
    final text = iPay
        ? l10n.settleSuggestYouOwe(nameOf(toUser), formatted)
        : iReceive
        ? l10n.settleSuggestOwesYou(nameOf(fromUser), formatted)
        : l10n.settleSuggestOther(nameOf(fromUser), nameOf(toUser), formatted);
    final (IconData icon, Color color) = iPay
        ? (Icons.north_east_rounded, palette.negativeAmount)
        : iReceive
        ? (Icons.south_west_rounded, palette.positiveAmount)
        : (Icons.swap_horiz_rounded, palette.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: AppSizes.iconSm, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textPrimary),
            ),
          ),
          if (iPay)
            Tooltip(
              message: l10n.settlePayTooltip(nameOf(toUser), formatted),
              child: TextButton(onPressed: onPay, child: Text(l10n.settlePay)),
            ),
        ],
      ),
    );
  }
}

/// One recorded payment with its status badge. The payee confirms a
/// pending payment; payer, payee or admin can void one. A payment with
/// someone who has left the group is [locked]: it shows why and offers
/// no actions (the server would refuse them).
class SettlementTile extends StatelessWidget {
  /// Creates the tile.
  const SettlementTile({
    required this.settlement,
    required this.currentUserId,
    required this.isGroupAdmin,
    required this.locked,
    required this.nameOf,
    required this.onConfirm,
    required this.onVoid,
    super.key,
  });

  /// The payment.
  final Settlement settlement;

  /// The signed-in user.
  final String? currentUserId;

  /// Whether the signed-in user is the group's admin.
  final bool isGroupAdmin;

  /// Whether someone in the payment has left the group.
  final bool locked;

  /// Names user ids.
  final MemberNamer nameOf;

  /// Confirms the payment.
  final VoidCallback onConfirm;

  /// Voids the payment.
  final VoidCallback onVoid;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final s = settlement;
    final canConfirm = !locked && s.canConfirm(currentUserId);
    final canVoid =
        !locked && s.canVoid(currentUserId, isGroupAdmin: isGroupAdmin);
    final details = <String>[
      if (s.isPending)
        s.toUser == currentUserId
            ? l10n.settlePendingForYou
            : l10n.settlePendingFor(nameOf(s.toUser)),
      DateHelpers.formatShortDate(s.createdAt),
      if (s.note case final note? when note.trim().isNotEmpty) note.trim(),
      if (s.isVoided)
        if (s.voidReason case final reason? when reason.trim().isNotEmpty)
          l10n.settleVoidReason(reason.trim()),
    ];
    final secondary = textTheme.bodySmall?.copyWith(
      color: palette.textSecondary,
    );

    return Padding(
      key: Key('settlement-${s.id}'),
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: palette.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            l10n.settlePaidRow(
                              nameOf(s.fromUser),
                              nameOf(s.toUser),
                            ),
                            style: textTheme.titleSmall?.copyWith(
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          MoneyFormat.format(s.amount),
                          style: textTheme.titleSmall?.copyWith(
                            color: s.isVoided
                                ? palette.textSecondary
                                : palette.textPrimary,
                            decoration: s.isVoided
                                ? TextDecoration.lineThrough
                                : null,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusBadge(switch (s.status) {
                          SettlementStatus.pending => StatusBadgeKind.pending,
                          SettlementStatus.confirmed =>
                            StatusBadgeKind.confirmed,
                          SettlementStatus.voided => StatusBadgeKind.voided,
                        }),
                        Text(details.join(' · '), style: secondary),
                      ],
                    ),
                  ],
                ),
              ),
              if (locked && !s.isVoided) ...[
                const SizedBox(height: AppSpacing.sm),
                InlineNotice(
                  key: Key('settlement-locked-${s.id}'),
                  kind: NoticeKind.locked,
                  message: friendlyMessageForKey(
                    'settlement_locked_member_left',
                  ),
                ),
              ],
              if (canConfirm || canVoid) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    if (canVoid)
                      TextButton(
                        key: Key('settlement-void-${s.id}'),
                        onPressed: onVoid,
                        child: Text(l10n.settleVoid),
                      ),
                    if (canConfirm)
                      FilledButton(
                        key: Key('settlement-confirm-${s.id}'),
                        onPressed: onConfirm,
                        child: Text(l10n.settleConfirm),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
