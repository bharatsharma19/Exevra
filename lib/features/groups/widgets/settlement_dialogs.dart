import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure_messages.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/utils/money_parser.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/balance.dart';
import '../../../models/group.dart';
import '../../../models/money.dart';
import '../../../models/settlement.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/group_detail_providers.dart';
import '../../expenses/widgets/inline_notice.dart';
import '../../expenses/widgets/money_input_field.dart';
import 'group_dialogs.dart';
import 'settlement_rows.dart';

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
    showMessage(context, context.l10n.settleNoOneToPay);
    return;
  }
  final recorded = await showDialog<String>(
    context: context,
    builder: (_) => _RecordPaymentDialog(
      group: group,
      userId: userId,
      others: others,
      toUser: toUser,
      amount: amount,
    ),
  );
  if (recorded != null && context.mounted) {
    showMessage(
      context,
      context.l10n.settleRecorded(recorded),
      kind: AppSnackbarKind.success,
    );
  }
}

class _RecordPaymentDialog extends ConsumerStatefulWidget {
  const _RecordPaymentDialog({
    required this.group,
    required this.userId,
    required this.others,
    this.toUser,
    this.amount,
  });

  final Group group;
  final String userId;
  final List<GroupMember> others;
  final String? toUser;
  final Money? amount;

  @override
  ConsumerState<_RecordPaymentDialog> createState() =>
      _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends ConsumerState<_RecordPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late String _payee;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final amount = widget.amount;
    _amount = TextEditingController(
      text: amount != null && amount.isPositive
          ? MoneyFormat.forInput(amount)
          : '',
    );
    _note = TextEditingController();
    _payee = widget.others.any((m) => m.userId == widget.toUser)
        ? widget.toUser!
        : widget.others.first.userId;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String get _payeeName =>
      widget.others.firstWhere((m) => m.userId == _payee).label;

  Future<void> _submit(int? limit) async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    final parsed = MoneyInputField.parse(
      _amount.text,
      currency: widget.group.currency,
    );
    if (parsed is! MoneyParsed) return;
    final name = _payeeName;
    setState(() {
      _busy = true;
      _error = null;
    });
    AppHaptics.light();
    final failure = await ref
        .read(settlementsProvider(widget.group.id).notifier)
        .record(
          toUser: _payee,
          amount: parsed.value,
          note: _note.text.trim(),
          report: false,
        );
    if (!mounted) return;
    if (failure != null) {
      AppHaptics.error();
      setState(() {
        _busy = false;
        _error = friendlyMessage(failure);
      });
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final group = widget.group;
    final balances = ref.watch(groupBalancesProvider(group.id)).value;
    // All pending payments count, not only the loaded history.
    final pending = ref.watch(pendingSettlementsProvider(group.id)).value;
    final limit = balances == null || pending == null
        ? null
        : settlementLimit(
            payer: widget.userId,
            payee: _payee,
            balances: balances,
            settlements: pending,
          );
    final limitMoney = limit == null ? null : Money(limit, group.currency);
    final nothingOwed = limit == 0;
    final payeeName = _payeeName;

    return AlertDialog(
      scrollable: true,
      title: Text(l10n.settleRecordTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.settleRecordIntro),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: const Key('payment-payee'),
              initialValue: _payee,
              decoration: InputDecoration(
                labelText: l10n.settlePaidTo,
                prefixIcon: const Icon(Icons.person_outline_rounded),
              ),
              items: [
                for (final m in widget.others)
                  DropdownMenuItem(
                    value: m.userId,
                    child: Text(m.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value == null) return;
                      AppHaptics.selection();
                      setState(() => _payee = value);
                    },
            ),
            const SizedBox(height: AppSpacing.md),
            MoneyInputField(
              key: const Key('payment-amount'),
              controller: _amount,
              currency: group.currency,
              label: l10n.settleAmountLabel(group.currency),
              enabled: !_busy && !nothingOwed,
              textInputAction: TextInputAction.next,
              helperText: limitMoney == null || nothingOwed
                  ? null
                  : l10n.settleLimitHelper(
                      payeeName,
                      MoneyFormat.format(limitMoney),
                    ),
              validator: (parsed) =>
                  limit != null && parsed.value.amountMinor > limit
                  ? l10n.settleOverLimit(
                      payeeName,
                      MoneyFormat.format(limitMoney!),
                    )
                  : null,
            ),
            if (nothingOwed) ...[
              const SizedBox(height: AppSpacing.sm),
              InlineNotice(
                key: const Key('payment-nothing-owed'),
                message: l10n.settleNothingOwed(payeeName),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('payment-note'),
              controller: _note,
              enabled: !_busy,
              maxLength: 200,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: l10n.settleNoteLabel,
                hintText: l10n.settleNoteHint,
                prefixIcon: const Icon(Icons.notes_rounded),
              ),
            ),
            if (_error != null) DialogError(_error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        LoadingButton(
          key: const Key('payment-record'),
          expand: false,
          isLoading: _busy,
          label: l10n.settleRecordPayment,
          onPressed: nothingOwed ? null : () => _submit(limit),
        ),
      ],
    );
  }
}

/// Voids a payment with an optional reason (payer, payee or admin).
Future<void> showVoidPaymentDialog(
  BuildContext context,
  WidgetRef ref,
  Group group,
  Settlement settlement,
  MemberNamer nameOf,
) async {
  final voided = await showDialog<bool>(
    context: context,
    builder: (_) => _VoidPaymentDialog(
      group: group,
      settlement: settlement,
      nameOf: nameOf,
    ),
  );
  if ((voided ?? false) && context.mounted) {
    showMessage(context, context.l10n.settleVoided);
  }
}

class _VoidPaymentDialog extends ConsumerStatefulWidget {
  const _VoidPaymentDialog({
    required this.group,
    required this.settlement,
    required this.nameOf,
  });

  final Group group;
  final Settlement settlement;
  final MemberNamer nameOf;

  @override
  ConsumerState<_VoidPaymentDialog> createState() => _VoidPaymentDialogState();
}

class _VoidPaymentDialogState extends ConsumerState<_VoidPaymentDialog> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    AppHaptics.heavy();
    final reason = _reason.text.trim();
    final failure = await ref
        .read(settlementsProvider(widget.group.id).notifier)
        .voidPayment(
          widget.settlement.id,
          reason: reason.isEmpty ? null : reason,
          report: false,
        );
    if (!mounted) return;
    if (failure != null) {
      AppHaptics.error();
      setState(() {
        _busy = false;
        _error = friendlyMessage(failure);
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = widget.settlement;
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.settleVoidTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.settleVoidMessage(
              widget.nameOf(s.fromUser),
              widget.nameOf(s.toUser),
              MoneyFormat.format(s.amount),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('void-reason'),
            controller: _reason,
            enabled: !_busy,
            maxLength: 200,
            decoration: InputDecoration(
              labelText: l10n.settleVoidReasonLabel,
              hintText: l10n.settleVoidReasonHint,
            ),
          ),
          if (_error != null) DialogError(_error!),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.settleKeep),
        ),
        LoadingButton(
          key: const Key('void-confirm'),
          expand: false,
          isLoading: _busy,
          variant: LoadingButtonVariant.destructive,
          label: l10n.settleVoidAction,
          onPressed: _submit,
        ),
      ],
    );
  }
}
