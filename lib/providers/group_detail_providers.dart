import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_failure.dart';
import '../core/logging/app_logger.dart';
import '../core/utils/haptics.dart';
import '../data/repositories/expense_repository.dart';
import '../data/repositories/group_repository.dart';
import '../data/repositories/invitation_repository.dart';
import '../data/repositories/settlement_repository.dart';
import '../models/balance.dart';
import '../models/group.dart';
import '../models/invitation.dart';
import '../models/money.dart';
import '../models/settlement.dart';
import 'auth_provider.dart';
import 'data_revision.dart';
import 'failure_reporter.dart';
import 'groups_provider.dart';

/// Group data is only loaded for a signed-in user; this throws for a
/// signed-out one so no stale data is shown.
String _requireUser(Ref ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) throw const AppFailure.sessionExpired();
  return userId;
}

AppFailure _report(Ref ref, AppFailure failure, {bool report = true}) {
  AppHaptics.error();
  if (report && ref.mounted) {
    ref.read(failureReporterProvider.notifier).report(failure);
  }
  return failure;
}

/// Members of a group as other members see them (no email or phone).
/// Pending join requests are included only for the admin.
class GroupMembersNotifier extends AsyncNotifier<List<GroupMember>> {
  GroupMembersNotifier(this.groupId);

  final String groupId;

  GroupRepository get _repo => ref.read(groupRepositoryProvider);

  @override
  Future<List<GroupMember>> build() async {
    _requireUser(ref);
    ref.watch(dataRevisionProvider.select((r) => r.members));
    return ref.watch(groupRepositoryProvider).fetchMembers(groupId);
  }

  Future<AppFailure?> _act(
    Future<void> Function() action, {
    bool report = true,
  }) async {
    try {
      await action();
      AppHaptics.success();
      if (!ref.mounted) return null;
      ref.read(dataRevisionProvider.notifier).bump(DataKind.members);
      // Roles and member counts on the group list change too.
      await ref.read(groupsProvider.notifier).refresh();
      return null;
    } on AppFailure catch (failure) {
      return _report(ref, failure, report: report);
    }
  }

  /// Approves a pending join request with [role] (member or viewer).
  Future<AppFailure?> approve(
    String userId, {
    GroupRole role = GroupRole.member,
  }) => _act(() => _repo.approveMember(groupId, userId, role: role));

  /// Removes a member or rejects a pending request. A member with an open
  /// balance needs [force] (the server answers `outstanding_balance`
  /// otherwise).
  Future<AppFailure?> remove(
    String userId, {
    bool force = false,
    bool report = true,
  }) => _act(
    () => _repo.removeMember(groupId, userId, force: force),
    report: report,
  );

  Future<AppFailure?> setRole(String userId, GroupRole role) =>
      _act(() => _repo.setMemberRole(groupId, userId, role));

  /// Makes [userId] the admin; the caller becomes a member.
  Future<AppFailure?> transferAdmin(String userId) =>
      _act(() => _repo.transferAdmin(groupId, userId));
}

final groupMembersProvider = AsyncNotifierProvider.autoDispose
    .family<GroupMembersNotifier, List<GroupMember>, String>(
      GroupMembersNotifier.new,
    );

/// Members of the active group, or an empty list in personal mode.
final activeGroupMembersProvider =
    Provider.autoDispose<AsyncValue<List<GroupMember>>>((ref) {
      final group = ref.watch(activeGroupProvider);
      if (group == null || !group.canRead) return const AsyncData([]);
      return ref.watch(groupMembersProvider(group.id));
    });

/// Per-member balances of a group (positive = others owe them).
final groupBalancesProvider = FutureProvider.autoDispose
    .family<List<GroupBalance>, String>((ref, groupId) {
      _requireUser(ref);
      ref.watch(dataRevisionProvider.select((r) => r.expenses));
      ref.watch(dataRevisionProvider.select((r) => r.settlements));
      ref.watch(dataRevisionProvider.select((r) => r.members));
      return ref.watch(balanceRepositoryProvider).balances(groupId);
    });

/// Fewest transfers that settle a group (pending payments accounted for).
final settleSuggestionsProvider = FutureProvider.autoDispose
    .family<List<SettleSuggestion>, String>((ref, groupId) {
      _requireUser(ref);
      ref.watch(dataRevisionProvider.select((r) => r.expenses));
      ref.watch(dataRevisionProvider.select((r) => r.settlements));
      ref.watch(dataRevisionProvider.select((r) => r.members));
      return ref.watch(balanceRepositoryProvider).suggestions(groupId);
    });

/// Settlements of a group, newest first, with record / confirm / void.
///
/// A recorded payment stays pending until the payee confirms it; only
/// confirmed payments count in balances.
class SettlementsNotifier extends AsyncNotifier<List<Settlement>> {
  SettlementsNotifier(this.groupId);

  final String groupId;

  SettlementRepository get _repo => ref.read(settlementRepositoryProvider);

  @override
  Future<List<Settlement>> build() async {
    _requireUser(ref);
    ref.watch(dataRevisionProvider.select((r) => r.settlements));
    return ref.watch(settlementRepositoryProvider).list(groupId);
  }

  Future<AppFailure?> _write(
    Future<Settlement> Function() action, {
    bool report = true,
  }) async {
    try {
      final saved = await action();
      if (!ref.mounted) return null;
      final current = state.value ?? const <Settlement>[];
      state = AsyncData(
        [saved, ...current.where((s) => s.id != saved.id)]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );
      ref.read(dataRevisionProvider.notifier).bump(DataKind.settlements);
      AppHaptics.success();
      return null;
    } on AppFailure catch (failure) {
      return _report(ref, failure, report: report);
    }
  }

  /// Records that the caller paid [toUser]; pending until confirmed.
  Future<AppFailure?> record({
    required String toUser,
    required Money amount,
    String? note,
    bool report = true,
  }) => _write(
    () => _repo.record(
      groupId: groupId,
      toUser: toUser,
      amount: amount,
      note: note,
    ),
    report: report,
  );

  /// The payee confirms they received the payment.
  Future<AppFailure?> confirm(String settlementId) =>
      _write(() => _repo.confirm(settlementId));

  /// Payer, payee or admin cancels a payment.
  Future<AppFailure?> voidPayment(
    String settlementId, {
    String? reason,
    bool report = true,
  }) => _write(
    () => _repo.voidSettlement(settlementId, reason: reason),
    report: report,
  );
}

final settlementsProvider = AsyncNotifierProvider.autoDispose
    .family<SettlementsNotifier, List<Settlement>, String>(
      SettlementsNotifier.new,
    );

/// Audit trail of one settlement, oldest first.
final settlementEventsProvider = FutureProvider.autoDispose
    .family<List<SettlementEvent>, String>((ref, settlementId) {
      _requireUser(ref);
      ref.watch(dataRevisionProvider.select((r) => r.settlements));
      return ref.watch(settlementRepositoryProvider).events(settlementId);
    });

/// Pending email invitations of a group (admin only), with send and
/// revoke.
class PendingInvitationsNotifier extends AsyncNotifier<List<GroupInvitation>> {
  PendingInvitationsNotifier(this.groupId);

  final String groupId;

  InvitationRepository get _repo => ref.read(invitationRepositoryProvider);

  @override
  Future<List<GroupInvitation>> build() async {
    _requireUser(ref);
    return ref.watch(invitationRepositoryProvider).listPending(groupId);
  }

  /// Creates an invitation and asks the server to email it. When the
  /// email could not be sent the result says so and carries a share link;
  /// it never claims an email was sent when it was not.
  Future<(SentInvitation?, AppFailure?)> send(
    String email, {
    GroupRole role = GroupRole.member,
    bool report = true,
  }) async {
    try {
      final sent = await _repo.send(groupId: groupId, email: email, role: role);
      AppHaptics.success();
      if (ref.mounted) ref.invalidateSelf();
      return (sent, null);
    } on AppFailure catch (failure) {
      return (null, _report(ref, failure, report: report));
    }
  }

  Future<AppFailure?> revoke(String invitationId) async {
    final before = state.value;
    if (before != null) {
      state = AsyncData(before.where((i) => i.id != invitationId).toList());
    }
    try {
      await _repo.revoke(invitationId);
      AppHaptics.medium();
      return null;
    } on AppFailure catch (failure) {
      if (ref.mounted && before != null) state = AsyncData(before);
      return _report(ref, failure);
    }
  }
}

final pendingInvitationsProvider = AsyncNotifierProvider.autoDispose
    .family<PendingInvitationsNotifier, List<GroupInvitation>, String>(
      PendingInvitationsNotifier.new,
    );

/// Invitation details for the signed-in invitee.
final invitationDetailsProvider = FutureProvider.autoDispose
    .family<InvitationDetails, String>((ref, token) {
      _requireUser(ref);
      return ref.watch(invitationRepositoryProvider).details(token);
    });

/// Keeps a realtime channel open for the active group and marks expenses,
/// members and settlements as changed when the server reports a change.
/// Watched by the main shell while signed in.
final groupRealtimeProvider = Provider.autoDispose<void>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  final group = ref.watch(activeGroupProvider);
  if (userId == null || group == null || !group.canRead) return;

  final pending = <DataKind>{};
  Timer? debounce;
  final subscription = ref
      .watch(expenseRepositoryProvider)
      .watchGroup(group.id)
      .listen(
        (kind) {
          pending.add(switch (kind) {
            GroupChangeKind.expenses => DataKind.expenses,
            GroupChangeKind.members => DataKind.members,
            GroupChangeKind.settlements => DataKind.settlements,
          });
          debounce?.cancel();
          // Bursts (bulk changes) cause one reload.
          debounce = Timer(const Duration(milliseconds: 400), () {
            final revisions = ref.read(dataRevisionProvider.notifier);
            for (final k in pending) {
              revisions.bump(k);
            }
            if (pending.contains(DataKind.members)) {
              unawaited(ref.read(groupsProvider.notifier).refresh());
            }
            pending.clear();
          });
        },
        onError: (Object error, StackTrace stackTrace) {
          AppLogger.warn('Realtime channel error', error.runtimeType);
        },
      );
  ref.onDispose(() {
    debounce?.cancel();
    unawaited(subscription.cancel());
  });
});
