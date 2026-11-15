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
import 'expense_provider.dart';
import 'groups_provider.dart';
import 'user_scoped.dart';

// Group data is only loaded for a signed-in user. Every provider here is
// a [UserScopedNotifier]: signed out it fails with "session expired", and
// when the user changes it starts over at loading, so no data of the
// previous user is shown. Every write captures a [SessionGuard] and drops
// its result (state, follow-up calls, failure reports) once that session
// has ended.

/// Members of a group as other members see them (no email or phone).
/// Pending join requests are included only for the admin.
class GroupMembersNotifier extends UserScopedFuture<List<GroupMember>> {
  GroupMembersNotifier(this.groupId)
    : super((ref, _) {
        ref.watch(dataRevisionProvider.select((r) => r.members));
        return ref.watch(groupRepositoryProvider).fetchMembers(groupId);
      });

  final String groupId;

  GroupRepository get _repo => ref.read(groupRepositoryProvider);

  Future<AppFailure?> _act(
    Future<void> Function() run, {
    bool report = true,
  }) async {
    const action = 'a member change';
    final session = guard();
    if (!session.holds(action)) return SessionGuard.dropped;
    try {
      await run();
      if (!session.holds(action)) return SessionGuard.dropped;
      AppHaptics.success();
      ref.read(dataRevisionProvider.notifier).bump(DataKind.members);
      // Roles and member counts on the group list change too.
      await ref.read(groupsProvider.notifier).refresh();
      return session.holds(action) ? null : SessionGuard.dropped;
    } on AppFailure catch (failure) {
      return session.fail(failure, action, report: report);
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

final groupMembersProvider = NotifierProvider.autoDispose
    .family<GroupMembersNotifier, AsyncValue<List<GroupMember>>, String>(
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
final groupBalancesProvider = NotifierProvider.autoDispose
    .family<
      UserScopedFuture<List<GroupBalance>>,
      AsyncValue<List<GroupBalance>>,
      String
    >(
      (groupId) => UserScopedFuture((ref, _) {
        ref.watch(dataRevisionProvider.select((r) => r.expenses));
        ref.watch(dataRevisionProvider.select((r) => r.settlements));
        ref.watch(dataRevisionProvider.select((r) => r.members));
        return ref.watch(balanceRepositoryProvider).balances(groupId);
      }),
    );

/// Fewest transfers that settle a group (pending payments accounted for).
final settleSuggestionsProvider = NotifierProvider.autoDispose
    .family<
      UserScopedFuture<List<SettleSuggestion>>,
      AsyncValue<List<SettleSuggestion>>,
      String
    >(
      (groupId) => UserScopedFuture((ref, _) {
        ref.watch(dataRevisionProvider.select((r) => r.expenses));
        ref.watch(dataRevisionProvider.select((r) => r.settlements));
        ref.watch(dataRevisionProvider.select((r) => r.members));
        return ref.watch(balanceRepositoryProvider).suggestions(groupId);
      }),
    );

/// Every pending payment of a group (not only the loaded history), for
/// the amount a payer may still record.
final pendingSettlementsProvider = NotifierProvider.autoDispose
    .family<
      UserScopedFuture<List<Settlement>>,
      AsyncValue<List<Settlement>>,
      String
    >(
      (groupId) => UserScopedFuture((ref, _) {
        ref.watch(dataRevisionProvider.select((r) => r.settlements));
        return ref.watch(settlementRepositoryProvider).pending(groupId);
      }),
    );

/// The loaded part of a group's payment history.
class SettlementHistory {
  const SettlementHistory({
    this.items = const [],
    this.hasMore = false,
    this.isLoadingMore = false,
    this.loadMoreFailure,
  });

  /// Newest first (`created_at DESC, id DESC`).
  final List<Settlement> items;
  final bool hasMore;
  final bool isLoadingMore;

  /// Why the last "load more" failed.
  final AppFailure? loadMoreFailure;
}

/// Settlements of a group, newest first and paged, with record / confirm
/// / void.
///
/// A recorded payment stays pending until the payee confirms it; only
/// confirmed payments count in balances.
///
/// A page of older payments is only appended to the list it was asked
/// for: when the list was reloaded meanwhile (a new first page, possibly
/// with newer payments in front) the page is dropped, so the history never
/// has a gap.
class SettlementsNotifier extends UserScopedNotifier<SettlementHistory> {
  SettlementsNotifier(this.groupId);

  final String groupId;

  static const int pageSize = 50;

  /// Moves whenever a load of the first page starts or lands.
  int _generation = 0;

  SettlementRepository get _repo => ref.read(settlementRepositoryProvider);

  @override
  AsyncValue<SettlementHistory> whenSignedOut() =>
      const AsyncError(AppFailure.sessionExpired(), StackTrace.empty);

  @override
  Future<SettlementHistory> fetch(String userId) async {
    _generation++;
    ref.watch(dataRevisionProvider.select((r) => r.settlements));
    final rows = await ref
        .watch(settlementRepositoryProvider)
        .list(groupId, limit: pageSize + 1);
    return SettlementHistory(
      items: rows.take(pageSize).toList(),
      hasMore: rows.length > pageSize,
    );
  }

  @override
  void onLoaded(String userId, SettlementHistory value) => _generation++;

  /// Whether a page that follows [cursor], asked for in [generation], may
  /// be appended to [now].
  bool _continues(SettlementHistory now, Settlement cursor, int generation) =>
      generation == _generation &&
      now.items.isNotEmpty &&
      now.items.last.id == cursor.id;

  /// Drops a page that no longer fits the list, ending its spinner.
  void _dropPage() {
    final now = state.value;
    if (!ref.mounted || now == null || !now.isLoadingMore) return;
    state = AsyncData(
      SettlementHistory(items: now.items, hasMore: now.hasMore),
    );
  }

  /// Loads the next page of older payments.
  Future<void> loadMore() async {
    const action = 'a payment history page';
    final session = guard();
    final current = state.value;
    if (!session.holds(action) ||
        current == null ||
        !current.hasMore ||
        current.isLoadingMore ||
        current.items.isEmpty ||
        isReloading) {
      return;
    }
    final generation = _generation;
    final cursor = current.items.last;
    state = AsyncData(
      SettlementHistory(
        items: current.items,
        hasMore: true,
        isLoadingMore: true,
      ),
    );
    try {
      final rows = await _repo.list(
        groupId,
        after: cursor,
        limit: pageSize + 1,
      );
      if (!session.holds(action)) return;
      final now = state.value;
      if (now == null || !_continues(now, cursor, generation)) {
        _dropPage();
        return;
      }
      final known = {for (final s in now.items) s.id};
      state = AsyncData(
        SettlementHistory(
          items: [
            ...now.items,
            ...rows.take(pageSize).where((s) => !known.contains(s.id)),
          ],
          hasMore: rows.length > pageSize,
        ),
      );
    } on AppFailure catch (failure) {
      if (!session.holds(action)) return;
      final now = state.value;
      if (now == null || !_continues(now, cursor, generation)) {
        _dropPage();
        return;
      }
      state = AsyncData(
        SettlementHistory(
          items: now.items,
          hasMore: true,
          loadMoreFailure: failure,
        ),
      );
    }
  }

  /// Newest first, ties by id (the server's order).
  static int _newestFirst(Settlement a, Settlement b) {
    final byTime = b.createdAt.compareTo(a.createdAt);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  }

  /// Writes on their way: `record` for a new payment, else the payment's
  /// id. The same write is not sent twice while the first is on its way.
  final Set<String> _inFlight = {};

  /// Runs one write. Like expense writes it is bounded by a timeout in the
  /// repository; a write that failed on the way may still have happened,
  /// so everything reloads and the failure says the result is unknown
  /// instead of inviting a retry that could record a payment twice.
  Future<AppFailure?> _write(
    String target,
    Future<Settlement> Function() run, {
    bool report = true,
  }) async {
    const action = 'a payment write';
    final session = guard();
    if (!session.holds(action)) return SessionGuard.dropped;
    if (!_inFlight.add(target)) {
      return session.fail(
        const AppFailure.business('settlement_in_progress'),
        action,
        report: report,
      );
    }
    try {
      final saved = await run();
      if (!session.holds(action)) return SessionGuard.dropped;
      final current = state.value ?? const SettlementHistory();
      state = AsyncData(
        SettlementHistory(
          items: [saved, ...current.items.where((s) => s.id != saved.id)]
            ..sort(_newestFirst),
          hasMore: current.hasMore,
          isLoadingMore: current.isLoadingMore,
          loadMoreFailure: current.loadMoreFailure,
        ),
      );
      ref.read(dataRevisionProvider.notifier).bump(DataKind.settlements);
      AppHaptics.success();
      return null;
    } on AppFailure catch (failure) {
      if (!session.holds(action)) return SessionGuard.dropped;
      if (!failure.outcomeUnknown) {
        return session.fail(failure, action, report: report);
      }
      ref.read(dataRevisionProvider.notifier).bump(DataKind.settlements);
      return session.fail(
        const AppFailure.network(key: 'settlement_unconfirmed'),
        action,
        report: report,
      );
    } finally {
      _inFlight.remove(target);
    }
  }

  /// Records that the caller paid [toUser]; pending until confirmed.
  Future<AppFailure?> record({
    required String toUser,
    required Money amount,
    String? note,
    bool report = true,
  }) => _write(
    'record',
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
      _write(settlementId, () => _repo.confirm(settlementId));

  /// Payer, payee or admin cancels a payment.
  Future<AppFailure?> voidPayment(
    String settlementId, {
    String? reason,
    bool report = true,
  }) => _write(
    settlementId,
    () => _repo.voidSettlement(settlementId, reason: reason),
    report: report,
  );
}

final settlementsProvider = NotifierProvider.autoDispose
    .family<SettlementsNotifier, AsyncValue<SettlementHistory>, String>(
      SettlementsNotifier.new,
    );

/// Audit trail of one settlement, oldest first.
final settlementEventsProvider = NotifierProvider.autoDispose
    .family<
      UserScopedFuture<List<SettlementEvent>>,
      AsyncValue<List<SettlementEvent>>,
      String
    >(
      (settlementId) => UserScopedFuture((ref, _) {
        ref.watch(dataRevisionProvider.select((r) => r.settlements));
        return ref.watch(settlementRepositoryProvider).events(settlementId);
      }),
    );

/// Pending email invitations of a group (admin only), with send and
/// revoke.
class PendingInvitationsNotifier
    extends UserScopedFuture<List<GroupInvitation>> {
  PendingInvitationsNotifier(this.groupId)
    : super(
        (ref, _) =>
            ref.watch(invitationRepositoryProvider).listPending(groupId),
      );

  final String groupId;

  InvitationRepository get _repo => ref.read(invitationRepositoryProvider);

  /// Creates an invitation and asks the server to email it. When the
  /// email could not be sent the result says so and carries a share link;
  /// it never claims an email was sent when it was not.
  Future<(SentInvitation?, AppFailure?)> send(
    String email, {
    GroupRole role = GroupRole.member,
    bool report = true,
  }) async {
    const action = 'an invitation';
    final session = guard();
    if (!session.holds(action)) return (null, SessionGuard.dropped);
    try {
      final sent = await _repo.send(groupId: groupId, email: email, role: role);
      if (!session.holds(action)) return (null, SessionGuard.dropped);
      AppHaptics.success();
      ref.invalidateSelf();
      return (sent, null);
    } on AppFailure catch (failure) {
      return (null, session.fail(failure, action, report: report));
    }
  }

  Future<AppFailure?> revoke(String invitationId) async {
    const action = 'an invitation revocation';
    final session = guard();
    if (!session.holds(action)) return SessionGuard.dropped;
    final before = state.value;
    if (before != null) {
      state = AsyncData(before.where((i) => i.id != invitationId).toList());
    }
    try {
      await _repo.revoke(invitationId);
      if (!session.holds(action)) return SessionGuard.dropped;
      AppHaptics.medium();
      return null;
    } on AppFailure catch (failure) {
      if (!session.holds(action)) return SessionGuard.dropped;
      if (before != null) state = AsyncData(before);
      return session.fail(failure, action);
    }
  }
}

final pendingInvitationsProvider = NotifierProvider.autoDispose
    .family<
      PendingInvitationsNotifier,
      AsyncValue<List<GroupInvitation>>,
      String
    >(PendingInvitationsNotifier.new);

/// Invitation details for the signed-in invitee.
final invitationDetailsProvider = NotifierProvider.autoDispose
    .family<
      UserScopedFuture<InvitationDetails>,
      AsyncValue<InvitationDetails>,
      String
    >(
      (token) => UserScopedFuture(
        (ref, _) => ref.watch(invitationRepositoryProvider).details(token),
      ),
    );

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
        (change) {
          final deleted = change.deletedExpenseId;
          // Deletions arrive for every expense on the server; only those
          // a list shows matter here.
          if (deleted != null &&
              !ref.read(expenseListRegistryProvider).shows(deleted)) {
            return;
          }
          pending.add(switch (change.kind) {
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
