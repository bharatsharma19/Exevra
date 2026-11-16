import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/balance.dart';
import '../../../models/group.dart';
import '../../../models/settlement.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/group_detail_providers.dart';
import '../../expenses/widgets/inline_notice.dart';
import 'group_dialogs.dart';
import 'settlement_dialogs.dart';
import 'settlement_rows.dart';

export 'settlement_dialogs.dart';
export 'settlement_rows.dart';

/// Names for user ids in one group: "You", members, then balance rows
/// (departed members keep their name there), else "Former member".
MemberNamer memberNamer(
  AppLocalizations l10n, {
  required String? currentUserId,
  required List<GroupMember> members,
  required List<GroupBalance> balances,
}) {
  return (userId) {
    if (userId == null) return l10n.settleFormerMember;
    if (userId == currentUserId) return l10n.settleYou;
    for (final m in members) {
      if (m.userId == userId) return m.label;
    }
    for (final b in balances) {
      if (b.userId == userId) return b.displayName;
    }
    return l10n.settleFormerMember;
  };
}

/// Whether [settlement] is with someone who is no longer an approved
/// member of the group; the server then refuses to confirm or void it
/// (`settlement_locked_member_left`). Only known once [members] loaded.
bool isSettlementLocked(Settlement settlement, List<GroupMember>? members) {
  if (members == null || members.isEmpty || settlement.isVoided) return false;
  final approved = {
    for (final m in members)
      if (!m.isPending) m.userId,
  };
  bool gone(String? userId) => userId == null || !approved.contains(userId);
  return gone(settlement.fromUser) || gone(settlement.toUser);
}

/// Balances per member, settle-up suggestions, and payments with their
/// status. A recorded payment stays pending until the payee confirms it;
/// either party or the admin can void one, unless someone in it left.
class SettlementsCard extends ConsumerWidget {
  const SettlementsCard({super.key, required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final userId = ref.watch(currentUserIdProvider);
    final balancesAsync = ref.watch(groupBalancesProvider(group.id));
    final suggestionsAsync = ref.watch(settleSuggestionsProvider(group.id));
    final settlementsAsync = ref.watch(settlementsProvider(group.id));
    final loadedMembers = ref.watch(groupMembersProvider(group.id)).value;
    final members = loadedMembers ?? const <GroupMember>[];
    final balances = balancesAsync.value ?? const <GroupBalance>[];
    final nameOf = memberNamer(
      l10n,
      currentUserId: userId,
      members: members,
      balances: balances,
    );
    final canRecord = members.any((m) => !m.isPending && m.userId != userId);

    Widget heading(String text) => SectionHeader(
      title: text,
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
    );
    Widget note(String text, {Key? key}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Text(
        text,
        key: key,
        style: textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
      ),
    );
    const skeleton = SkeletonList(itemCount: 2, padding: EdgeInsets.zero);

    return AppCard(
      key: const Key('settlements-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.settleTitle,
                  style: textTheme.titleMedium?.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
              if (canRecord)
                TextButton.icon(
                  key: const Key('settlements-record'),
                  onPressed: () =>
                      unawaited(showRecordPaymentDialog(context, ref, group)),
                  icon: const Icon(Icons.handshake_outlined),
                  label: Text(l10n.settleRecordPayment),
                ),
            ],
          ),
          heading(l10n.settleBalancesHeader(group.currency)),
          ...balancesAsync.when(
            skipLoadingOnReload: true,
            loading: () => const [skeleton],
            error: (error, _) => [
              CompactRetry(
                error: error,
                onRetry: () => ref.invalidate(groupBalancesProvider(group.id)),
              ),
            ],
            data: (rows) => [
              for (final b in rows)
                BalanceRow(
                  name: b.userId == null ? nameOf(null) : b.displayName,
                  net: b.net,
                  isYou: b.userId != null && b.userId == userId,
                ),
            ],
          ),
          heading(l10n.settleSuggestionsHeader),
          ...suggestionsAsync.when(
            skipLoadingOnReload: true,
            loading: () => const [skeleton],
            error: (error, _) => [
              CompactRetry(
                error: error,
                onRetry: () =>
                    ref.invalidate(settleSuggestionsProvider(group.id)),
              ),
            ],
            data: (suggestions) => suggestions.isEmpty
                ? [
                    Semantics(
                      liveRegion: true,
                      child: note(
                        l10n.settleEveryoneSettled,
                        key: const Key('settled-up'),
                      ),
                    ),
                  ]
                : [
                    for (final s in suggestions)
                      SuggestionRow(
                        fromUser: s.fromUser,
                        toUser: s.toUser,
                        amount: s.amount,
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
          heading(l10n.settlePaymentsHeader),
          ...settlementsAsync.when(
            skipLoadingOnReload: true,
            loading: () => const [skeleton],
            error: (error, _) => [
              CompactRetry(
                error: error,
                onRetry: () => ref.invalidate(settlementsProvider(group.id)),
              ),
            ],
            data: (history) => history.items.isEmpty
                ? [note(l10n.settleNoPayments)]
                : [
                    for (final s in history.items)
                      SettlementTile(
                        settlement: s,
                        currentUserId: userId,
                        isGroupAdmin: group.isAdmin,
                        locked: isSettlementLocked(s, loadedMembers),
                        nameOf: nameOf,
                        onConfirm: () =>
                            unawaited(_confirm(context, ref, s, nameOf)),
                        onVoid: () => unawaited(
                          showVoidPaymentDialog(context, ref, group, s, nameOf),
                        ),
                      ),
                    if (history.loadMoreFailure case final failure?)
                      CompactRetry(
                        error: failure,
                        onRetry: () => unawaited(
                          ref
                              .read(settlementsProvider(group.id).notifier)
                              .loadMore(),
                        ),
                      )
                    else if (history.isLoadingMore)
                      const SkeletonList(itemCount: 1, padding: EdgeInsets.zero)
                    else if (history.hasMore)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          key: const Key('settlements-load-more'),
                          onPressed: () => unawaited(
                            ref
                                .read(settlementsProvider(group.id).notifier)
                                .loadMore(),
                          ),
                          icon: const Icon(Icons.expand_more_rounded),
                          label: Text(l10n.settleShowOlder),
                        ),
                      ),
                  ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref,
    Settlement s,
    MemberNamer nameOf,
  ) async {
    final l10n = context.l10n;
    final ok = await confirmAction(
      context,
      title: l10n.settleConfirmTitle,
      message: l10n.settleConfirmMessage(
        MoneyFormat.format(s.amount),
        nameOf(s.fromUser),
      ),
      confirmLabel: l10n.settleConfirmAction,
    );
    if (!ok) return;
    final failure = await ref
        .read(settlementsProvider(group.id).notifier)
        .confirm(s.id);
    if (failure == null && context.mounted) {
      showMessage(context, l10n.settleConfirmed, kind: AppSnackbarKind.success);
    }
  }
}
