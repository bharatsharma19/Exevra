import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_helpers.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/utils/money_parser.dart';
import '../../../models/balance.dart';
import '../../../models/group.dart';
import '../../../models/money.dart';
import '../../../models/settlement.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/group_detail_providers.dart';
import '../../shared/failure_retry.dart';
import 'group_dialogs.dart';

/// Names for user ids in one group: "You", members, then balance rows
/// (departed members keep their name there), else "Former member".
String Function(String? userId) _namer({
  required String? currentUserId,
  required List<GroupMember> members,
  required List<GroupBalance> balances,
}) {
  return (userId) {
    if (userId == null) return 'Former member';
    if (userId == currentUserId) return 'You';
    for (final m in members) {
      if (m.userId == userId) return m.label;
    }
    for (final b in balances) {
      if (b.userId == userId) return b.displayName;
    }
    return 'Former member';
  };
}

/// How much [payer] may still record to [payee] in minor units, mirroring
/// the server limit: what the payer still owes and what the payee is still
/// owed, after pending payments. Null when the balances are not loaded.
int? settlementLimit({
  required String payer,
  required String payee,
  required List<GroupBalance> balances,
  required List<Settlement> settlements,
}) {
  int? net(String userId) {
    for (final b in balances) {
      if (b.userId == userId) return b.net.amountMinor;
    }
    return null;
  }

  // Projected net = net + pending out - pending in.
  int projected(String userId, int base) {
    var value = base;
    for (final s in settlements.where((s) => s.isPending)) {
      if (s.fromUser == userId) value += s.amount.amountMinor;
      if (s.toUser == userId) value -= s.amount.amountMinor;
    }
    return value;
  }

  final payerNet = net(payer);
  final payeeNet = net(payee);
  if (payerNet == null || payeeNet == null) return null;
  final owes = -projected(payer, payerNet);
  final owed = projected(payee, payeeNet);
  return math.max(0, math.min(owes, owed));
}

/// Balances per member, settle-up suggestions, and payments with their
/// status. A recorded payment stays pending until the payee confirms it;
/// either party or the admin can void one.
class SettlementsCard extends ConsumerWidget {
  const SettlementsCard({super.key, required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final userId = ref.watch(currentUserIdProvider);
    final balancesAsync = ref.watch(groupBalancesProvider(group.id));
    final suggestionsAsync = ref.watch(settleSuggestionsProvider(group.id));
    final settlementsAsync = ref.watch(settlementsProvider(group.id));
    final members =
        ref.watch(groupMembersProvider(group.id)).value ??
        const <GroupMember>[];
    final balances = balancesAsync.value ?? const <GroupBalance>[];
    final nameOf = _namer(
      currentUserId: userId,
      members: members,
      balances: balances,
    );
    final canRecord = members.any((m) => !m.isPending && m.userId != userId);

    return GlassCard(
      key: const Key('settlements-card'),
      borderRadius: 20,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_rounded,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Balances & payments',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              if (canRecord)
                TextButton.icon(
                  onPressed: () =>
                      unawaited(showRecordPaymentDialog(context, ref, group)),
                  icon: const Icon(Icons.handshake_rounded, size: 16),
                  label: const Text('Record payment'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _Subheading('Balances (${group.currency})'),
          ...balancesAsync.when(
            skipLoadingOnReload: true,
            loading: () => const [LinearProgressIndicator()],
            error: (error, _) => [
              FailureRetry(
                error: error,
                compact: true,
                onRetry: () => ref.invalidate(groupBalancesProvider(group.id)),
              ),
            ],
            data: (rows) => [
              for (final b in rows)
                _BalanceRow(
                  name: b.userId == userId ? 'You' : b.displayName,
                  net: b.net,
                ),
            ],
          ),
          const SizedBox(height: 12),
          const _Subheading('Suggested payments'),
          ...suggestionsAsync.when(
            skipLoadingOnReload: true,
            loading: () => const [LinearProgressIndicator()],
            error: (error, _) => [
              FailureRetry(
                error: error,
                compact: true,
                onRetry: () =>
                    ref.invalidate(settleSuggestionsProvider(group.id)),
              ),
            ],
            data: (suggestions) => suggestions.isEmpty
                ? [
                    Text(
                      'Everyone is settled up.',
                      key: const Key('settled-up'),
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ]
                : [
                    for (final s in suggestions)
                      _SuggestionRow(
                        suggestion: s,
                        currentUserId: userId,
                        nameOf: nameOf,
                        onPay: () => unawaited(
                          showRecordPaymentDialog(
                            context,
                            ref,
                            group,
                            toUser: s.toUser,
                            amount: s.amount,
                          ),
                        ),
                      ),
                  ],
          ),
          const SizedBox(height: 12),
          const _Subheading('Payments'),
          ...settlementsAsync.when(
            skipLoadingOnReload: true,
            loading: () => const [LinearProgressIndicator()],
            error: (error, _) => [
              FailureRetry(
                error: error,
                compact: true,
                onRetry: () => ref.invalidate(settlementsProvider(group.id)),
              ),
            ],
            data: (rows) => rows.isEmpty
                ? [
                    Text(
                      'No payments recorded yet.',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ]
                : [
                    for (final s in rows)
                      _SettlementTile(
                        group: group,
                        settlement: s,
                        currentUserId: userId,
                        nameOf: nameOf,
                      ),
                  ],
          ),
        ],
      ),
    );
  }
}

class _Subheading extends StatelessWidget {
  const _Subheading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.name, required this.net});

  final String name;
  final Money net;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final you = name == 'You';
    final String status;
    final Color color;
    if (net.isPositive) {
      status = '${you ? 'are' : 'is'} owed ${MoneyFormat.format(net)}';
      color = AppColors.primaryEmerald;
    } else if (net.isNegative) {
      status = '${you ? 'owe' : 'owes'} ${MoneyFormat.format(net.abs())}';
      color = AppColors.primaryRose;
    } else {
      status = '${you ? 'are' : 'is'} settled up';
      color = scheme.onSurfaceVariant;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Flexible(
            child: Text(
              status,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.suggestion,
    required this.currentUserId,
    required this.nameOf,
    required this.onPay,
  });

  final SettleSuggestion suggestion;
  final String? currentUserId;
  final String Function(String?) nameOf;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final iPay = suggestion.fromUser == currentUserId;
    final iReceive = suggestion.toUser == currentUserId;
    final text = iPay
        ? 'You pay ${nameOf(suggestion.toUser)}'
        : iReceive
        ? '${nameOf(suggestion.fromUser)} pays you'
        : '${nameOf(suggestion.fromUser)} pays ${nameOf(suggestion.toUser)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            iPay
                ? Icons.arrow_circle_up_rounded
                : iReceive
                ? Icons.arrow_circle_down_rounded
                : Icons.swap_horiz_rounded,
            size: 18,
            color: iPay
                ? AppColors.primaryRose
                : iReceive
                ? AppColors.primaryEmerald
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$text ${MoneyFormat.format(suggestion.amount)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          if (iPay) TextButton(onPressed: onPay, child: const Text('Pay')),
        ],
      ),
    );
  }
}

class _SettlementTile extends ConsumerWidget {
  const _SettlementTile({
    required this.group,
    required this.settlement,
    required this.currentUserId,
    required this.nameOf,
  });

  final Group group;
  final Settlement settlement;
  final String? currentUserId;
  final String Function(String?) nameOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final s = settlement;
    final payee = s.toUser == currentUserId ? 'you' : nameOf(s.toUser);
    final status = switch (s.status) {
      SettlementStatus.pending => 'Pending: waiting for $payee to confirm',
      SettlementStatus.confirmed => 'Confirmed',
      SettlementStatus.voided =>
        s.voidReason == null || s.voidReason!.trim().isEmpty
            ? 'Voided'
            : 'Voided: ${s.voidReason}',
    };
    final statusColor = switch (s.status) {
      SettlementStatus.pending => AppColors.warning,
      SettlementStatus.confirmed => AppColors.primaryEmerald,
      SettlementStatus.voided => scheme.onSurfaceVariant,
    };
    final canConfirm = s.canConfirm(currentUserId);
    final canVoid = s.canVoid(currentUserId, isGroupAdmin: group.isAdmin);
    return Container(
      key: Key('settlement-${s.id}'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${nameOf(s.fromUser)} paid ${nameOf(s.toUser)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                MoneyFormat.format(s.amount),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  decoration: s.isVoided ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$status • ${DateHelpers.formatShortDate(s.createdAt)}'
            '${s.note == null ? '' : ' • ${s.note}'}',
            style: TextStyle(fontSize: 12, color: statusColor),
          ),
          if (canConfirm || canVoid)
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 4,
                children: [
                  if (canVoid)
                    TextButton(
                      onPressed: () => unawaited(
                        showVoidPaymentDialog(context, ref, group, s, nameOf),
                      ),
                      child: const Text('Void'),
                    ),
                  if (canConfirm)
                    ElevatedButton(
                      onPressed: () => unawaited(_confirm(context, ref)),
                      child: const Text('Confirm'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final s = settlement;
    final ok = await confirmAction(
      context,
      title: 'Confirm this payment?',
      message:
          'Confirm only if you received ${MoneyFormat.format(s.amount)} from '
          '${nameOf(s.fromUser)}. It then counts in the balances.',
      confirmLabel: 'I received it',
    );
    if (!ok) return;
    final failure = await ref
        .read(settlementsProvider(group.id).notifier)
        .confirm(s.id);
    if (failure == null && context.mounted) {
      showMessage(context, 'Payment confirmed.');
    }
  }
}

/// Records a payment from the signed-in user to another member. It stays
/// pending until the payee confirms it, and can be at most what the user
/// still owes that person.
Future<void> showRecordPaymentDialog(
  BuildContext context,
  WidgetRef ref,
  Group group, {
  String? toUser,
  Money? amount,
}) async {
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) return;
  final members =
      ref.read(groupMembersProvider(group.id)).value ?? const <GroupMember>[];
  final others = members
      .where((m) => !m.isPending && m.userId != userId)
      .toList();
  if (others.isEmpty) {
    showMessage(context, 'There is no one else in this group to pay.');
    return;
  }
  var payee = others.any((m) => m.userId == toUser)
      ? toUser!
      : others.first.userId;
  var amountText = amount != null && amount.isPositive
      ? MoneyFormat.forInput(amount)
      : '';
  var noteText = '';
  var busy = false;
  String? amountError;
  String? error;

  await showDialog<void>(
    context: context,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final balances = ref.watch(groupBalancesProvider(group.id)).value;
        final settlements = ref.watch(settlementsProvider(group.id)).value;
        return StatefulBuilder(
          builder: (ctx, setState) {
            final payeeName = others.firstWhere((m) => m.userId == payee).label;
            final limit = balances == null || settlements == null
                ? null
                : settlementLimit(
                    payer: userId,
                    payee: payee,
                    balances: balances,
                    settlements: settlements,
                  );
            final limitMoney = limit == null
                ? null
                : Money(limit, group.currency);
            final nothingOwed = limit == 0;

            Future<void> submit() async {
              final parsed = MoneyParser.parse(
                amountText,
                currency: group.currency,
              );
              if (parsed is MoneyParseError) {
                setState(() => amountError = friendlyMessage(parsed.failure));
                return;
              }
              final value = (parsed as MoneyParsed).value;
              if (limit != null && value.amountMinor > limit) {
                setState(
                  () => amountError =
                      "That's more than you owe $payeeName "
                      '(up to ${MoneyFormat.format(limitMoney!)}).',
                );
                return;
              }
              setState(() {
                busy = true;
                amountError = null;
                error = null;
              });
              final failure = await ref
                  .read(settlementsProvider(group.id).notifier)
                  .record(
                    toUser: payee,
                    amount: value,
                    note: noteText,
                    report: false,
                  );
              if (!ctx.mounted) return;
              if (failure != null) {
                setState(() {
                  busy = false;
                  error = friendlyMessage(failure);
                });
                return;
              }
              Navigator.of(ctx).pop();
              if (context.mounted) {
                showMessage(
                  context,
                  'Payment recorded. It counts once $payeeName confirms it.',
                );
              }
            }

            return AlertDialog(
              title: const Text('Record a payment'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Record money you paid to a group member. It counts '
                      'once they confirm they received it.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      key: const Key('payment-payee'),
                      initialValue: payee,
                      decoration: const InputDecoration(
                        labelText: 'Paid to',
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                      items: [
                        for (final m in others)
                          DropdownMenuItem(
                            value: m.userId,
                            child: Text(m.label),
                          ),
                      ],
                      onChanged: busy
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() {
                                  payee = value;
                                  amountError = null;
                                });
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('payment-amount'),
                      initialValue: amountText,
                      onChanged: (value) => amountText = value,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Amount (${group.currency})',
                        prefixIcon: const Icon(Icons.payments_rounded),
                        helperText: limitMoney == null || nothingOwed
                            ? null
                            : 'You owe $payeeName up to '
                                  '${MoneyFormat.format(limitMoney)}.',
                        errorText: amountError,
                      ),
                    ),
                    if (nothingOwed) ...[
                      const SizedBox(height: 8),
                      Text(
                        "You don't owe $payeeName anything right now.",
                        key: const Key('payment-nothing-owed'),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      onChanged: (value) => noteText = value,
                      maxLength: 200,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                        hintText: 'e.g. UPI, cash, bank transfer',
                        prefixIcon: Icon(Icons.note_alt_outlined),
                      ),
                    ),
                    if (error != null) DialogError(error!),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  key: const Key('payment-record'),
                  onPressed: busy || nothingOwed ? null : submit,
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Record payment'),
                ),
              ],
            );
          },
        );
      },
    ),
  );
}

/// Voids a payment with an optional reason (payer, payee or admin).
Future<void> showVoidPaymentDialog(
  BuildContext context,
  WidgetRef ref,
  Group group,
  Settlement settlement,
  String Function(String?) nameOf,
) async {
  var reason = '';
  var busy = false;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Future<void> submit() async {
          setState(() {
            busy = true;
            error = null;
          });
          final failure = await ref
              .read(settlementsProvider(group.id).notifier)
              .voidPayment(
                settlement.id,
                reason: reason.trim().isEmpty ? null : reason.trim(),
                report: false,
              );
          if (!ctx.mounted) return;
          if (failure != null) {
            setState(() {
              busy = false;
              error = friendlyMessage(failure);
            });
            return;
          }
          Navigator.of(ctx).pop();
          if (context.mounted) showMessage(context, 'Payment voided.');
        }

        return AlertDialog(
          title: const Text('Void this payment?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${nameOf(settlement.fromUser)} paid '
                '${nameOf(settlement.toUser)} '
                '${MoneyFormat.format(settlement.amount)}. A voided payment no '
                'longer counts in the balances.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('void-reason'),
                onChanged: (value) => reason = value,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  hintText: 'e.g. Entered twice',
                ),
              ),
              if (error != null) DialogError(error!),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Keep it'),
            ),
            BusyButton(busy: busy, label: 'Void payment', onPressed: submit),
          ],
        );
      },
    ),
  );
}
