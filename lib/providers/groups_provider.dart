import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_failure.dart';
import '../core/logging/app_logger.dart';
import '../core/utils/haptics.dart';
import '../data/repositories/group_repository.dart';
import '../data/repositories/invitation_repository.dart';
import '../data/repositories/profile_repository.dart';
import '../models/group.dart';
import '../models/json_reader.dart';
import '../models/profile.dart';
import 'auth_provider.dart';
import 'profile_provider.dart';
import 'user_scoped.dart';

/// The user's groups and the active scope.
class GroupsState {
  const GroupsState({this.groups = const [], this.activeGroupId, this.userId});

  final List<Group> groups;

  /// Whose groups these are; null when signed out.
  final String? userId;

  /// The active group, or null for personal mode. Always an approved
  /// membership of [groups].
  final String? activeGroupId;

  Group? get activeGroup {
    final id = activeGroupId;
    if (id == null) return null;
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  bool get isPersonal => activeGroup == null;

  List<Group> get approvedGroups => groups.where((g) => g.isApproved).toList();
  List<Group> get pendingGroups => groups.where((g) => g.isPending).toList();

  GroupsState copyWith({List<Group>? groups, Object? activeGroupId = unset}) {
    return GroupsState(
      groups: groups ?? this.groups,
      activeGroupId: pick<String?>(activeGroupId, this.activeGroupId),
      userId: userId,
    );
  }
}

/// What became of a group creation.
enum GroupCreateStatus {
  /// Created and now the active group.
  opened,

  /// Created on the server, but the group list or the active scope could
  /// not be updated afterwards. Creating again would make a second group.
  createdNotOpened,

  /// The request failed on the way, so the group may or may not exist.
  /// The list was reloaded; the user checks it before trying again.
  unconfirmed,

  /// The server refused it; nothing was created. Also the result when the
  /// user changed while it ran ([SessionGuard.dropped]): nothing is done
  /// for or shown to the next user.
  failed,
}

/// Result of [GroupsNotifier.createGroup].
class GroupCreateResult {
  const GroupCreateResult(this.status, {this.failure});

  final GroupCreateStatus status;

  /// What went wrong, for every status but [GroupCreateStatus.opened].
  final AppFailure? failure;

  /// Whether the group exists on the server for certain.
  bool get created =>
      status == GroupCreateStatus.opened ||
      status == GroupCreateStatus.createdNotOpened;
}

/// Groups of the signed-in user plus the active scope (personal or one
/// group). The scope is stored on the server with `set_active_group`, and
/// each switch writes exactly once.
///
/// When the user changes the state starts over at loading with no value
/// (see [UserScopedNotifier]); [GroupsState.userId] names the owner.
class GroupsNotifier extends UserScopedNotifier<GroupsState> {
  GroupRepository get _repo => ref.read(groupRepositoryProvider);

  /// Number of the latest scope switch; only the latest one updates or
  /// rolls back the visible scope.
  int _scopeSwitches = 0;

  /// Scope writes run one after another so the server ends on the last.
  Future<void> _scopeWrites = Future.value();

  /// The active group the server holds as far as this device knows.
  String? _serverScope;

  @override
  AsyncValue<GroupsState> whenSignedOut() => const AsyncData(GroupsState());

  @override
  String? ownerOf(GroupsState value) => value.userId;

  @override
  Future<GroupsState> fetch(String userId) async {
    final repo = ref.watch(groupRepositoryProvider);
    // The saved scope is on the profile; reading it first makes sure it
    // is the profile of [userId] that loads.
    ref.read(profileProvider);
    final results = await Future.wait<Object?>([
      repo.fetchMyGroups(),
      ref.read(profileProvider.notifier).loaded,
    ]);
    final groups = results[0]! as List<Group>;
    final profile = results[1] as UserProfile?;
    final saved = profile?.id == userId ? profile?.activeGroupId : null;
    _serverScope = saved;
    return GroupsState(
      groups: groups,
      activeGroupId: _resolve(groups, saved),
      userId: userId,
    );
  }

  /// Loads again after a failure. When the profile is what failed (the
  /// groups need its saved scope), the profile is loaded again too.
  void retry() {
    if (ref.read(profileProvider).hasError) ref.invalidate(profileProvider);
    ref.invalidateSelf();
  }

  /// Whether the result of [action], started in [session], may be
  /// applied: the notifier is reused across sign-ins, so after an await
  /// the signed-in user (and the loaded state) may be someone else's.
  bool _applies(SessionGuard session, String action) {
    if (!session.holds(action)) return false;
    final owner = state.value?.userId;
    if (owner == null || owner == session.userId) return true;
    AppLogger.debug('Dropped the result of $action: other groups are loaded');
    return false;
  }

  /// The saved active group if it is still an approved membership.
  static String? _resolve(List<Group> groups, String? saved) {
    if (saved == null) return null;
    final match = groups.where((g) => g.id == saved && g.isApproved);
    return match.isEmpty ? null : saved;
  }

  /// Re-reads the group list, keeping the active scope when still valid.
  /// With [report] false a failure is only returned. When the user changed
  /// meanwhile the result is dropped and [SessionGuard.dropped] returned.
  Future<AppFailure?> refresh({bool report = true}) =>
      _refresh(guard(), report: report);

  Future<AppFailure?> _refresh(
    SessionGuard session, {
    bool report = true,
  }) async {
    const action = 'a groups refresh';
    if (!session.holds(action)) return SessionGuard.dropped;
    try {
      final groups = await _repo.fetchMyGroups();
      if (!_applies(session, action)) return SessionGuard.dropped;
      final active = state.value?.activeGroupId;
      state = AsyncData(
        GroupsState(
          groups: groups,
          activeGroupId: _resolve(groups, active),
          userId: session.userId,
        ),
      );
      return null;
    } on AppFailure catch (failure) {
      return session.fail(failure, action, report: report);
    }
  }

  /// Switches to [groupId] (null = personal). Writes the profile once per
  /// switch. Writes are sent in order, and when the latest switch fails
  /// the scope the server holds is shown again. With [report] false a
  /// failure is only returned.
  Future<AppFailure?> switchScope(String? groupId, {bool report = true}) =>
      _switchScope(guard(), groupId, report: report);

  Future<AppFailure?> _switchScope(
    SessionGuard session,
    String? groupId, {
    bool report = true,
  }) async {
    const action = 'a scope switch';
    final current = state.value;
    if (current == null || current.userId == null) return null;
    if (current.userId != session.userId || !_applies(session, action)) {
      return SessionGuard.dropped;
    }
    if (current.activeGroupId == groupId) return null;
    AppHaptics.selection();
    final number = ++_scopeSwitches;
    state = AsyncData(current.copyWith(activeGroupId: groupId));
    final write = _scopeWrites.then((_) {
      // Queued behind an earlier write: when the session ended meanwhile
      // the call would run as the next user.
      if (!session.holds(action)) throw SessionGuard.dropped;
      return _repo.setActiveGroup(groupId);
    });
    _scopeWrites = write.then<void>((_) {}, onError: (Object _) {});
    try {
      await write;
      if (!_applies(session, action)) return SessionGuard.dropped;
      _serverScope = groupId;
      if (number == _scopeSwitches) {
        ref.read(profileProvider.notifier).setActiveGroupLocally(groupId);
      }
      return null;
    } on AppFailure catch (failure) {
      if (!_applies(session, action)) return SessionGuard.dropped;
      // A later switch decides the scope (and reports its own failure).
      if (number != _scopeSwitches) return failure;
      final now = state.value ?? current;
      final restored = _resolve(now.groups, _serverScope);
      state = AsyncData(now.copyWith(activeGroupId: restored));
      ref.read(profileProvider.notifier).setActiveGroupLocally(restored);
      return session.fail(failure, action, report: report);
    }
  }

  /// What a group creation returns when the user changed while it ran.
  static const GroupCreateResult _droppedCreate = GroupCreateResult(
    GroupCreateStatus.failed,
    failure: SessionGuard.dropped,
  );

  /// Creates a group and makes it active. With [report] false failures
  /// are only returned (for a form that shows them itself).
  ///
  /// Once the server returned the new id the group exists, so a failure
  /// to reload or open it is never reported as a failure to create (a
  /// retry would make a second group). A request that failed on the way
  /// may also have created it: the list is reloaded and the result says
  /// so instead of inviting a retry.
  ///
  /// When the user changed while it ran nothing more is done for them (no
  /// reload, no `set_active_group`, no report) and the result is
  /// [GroupCreateStatus.failed] with [SessionGuard.dropped].
  Future<GroupCreateResult> createGroup(
    String name, {
    required String currency,
    bool report = true,
  }) async {
    const action = 'a group creation';
    final session = guard();
    if (!session.holds(action)) return _droppedCreate;
    final String id;
    try {
      id = await _repo.createGroup(name: name, currency: currency);
    } on AppFailure catch (failure) {
      if (!session.holds(action)) return _droppedCreate;
      if (failure.outcomeUnknown) {
        await _refresh(session, report: false);
        if (!session.holds(action)) return _droppedCreate;
        const unconfirmed = AppFailure.network(key: 'group_unconfirmed');
        session.fail(unconfirmed, action, report: report);
        return const GroupCreateResult(
          GroupCreateStatus.unconfirmed,
          failure: unconfirmed,
        );
      }
      session.fail(failure, action, report: report);
      return GroupCreateResult(GroupCreateStatus.failed, failure: failure);
    }
    if (!session.holds(action)) return _droppedCreate;
    // Opening needs the group in the list; without it the scope would
    // point at a group this device cannot show.
    final problem =
        await _refresh(session, report: report) ??
        await _switchScope(session, id, report: report);
    if (!session.holds(action)) return _droppedCreate;
    if (problem != null) {
      return GroupCreateResult(
        GroupCreateStatus.createdNotOpened,
        failure: problem,
      );
    }
    AppHaptics.success();
    return const GroupCreateResult(GroupCreateStatus.opened);
  }

  /// Sends a join request with an invite code. The group shows as
  /// pending until an admin approves.
  Future<(JoinRequest?, AppFailure?)> joinByCode(
    String code, {
    bool report = true,
  }) async {
    const action = 'a join request';
    final session = guard();
    if (!session.holds(action)) return (null, SessionGuard.dropped);
    try {
      final request = await _repo.joinByCode(code);
      if (!session.holds(action)) return (null, SessionGuard.dropped);
      await _refresh(session);
      if (!session.holds(action)) return (null, SessionGuard.dropped);
      AppHaptics.success();
      return (request, null);
    } on AppFailure catch (failure) {
      return (null, session.fail(failure, action, report: report));
    }
  }

  /// Issues a new invite code for [groupId] (admin only); the old code
  /// stops working.
  Future<(InviteCode?, AppFailure?)> rotateInviteCode(String groupId) async {
    const action = 'an invite code rotation';
    final session = guard();
    if (!session.holds(action)) return (null, SessionGuard.dropped);
    try {
      final code = await _repo.rotateInviteCode(groupId);
      if (!session.holds(action)) return (null, SessionGuard.dropped);
      await _refresh(session);
      if (!session.holds(action)) return (null, SessionGuard.dropped);
      AppHaptics.success();
      return (code, null);
    } on AppFailure catch (failure) {
      return (null, session.fail(failure, action));
    }
  }

  /// Accepts an email invitation; the server makes that group active.
  Future<AppFailure?> acceptInvitation(String token) async {
    const action = 'an invitation acceptance';
    final session = guard();
    if (!session.holds(action)) return SessionGuard.dropped;
    try {
      final groupId = await ref
          .read(invitationRepositoryProvider)
          .accept(token);
      if (!session.holds(action)) return SessionGuard.dropped;
      await _refresh(session);
      if (!_applies(session, action)) return SessionGuard.dropped;
      _serverScope = groupId;
      final current = state.value ?? GroupsState(userId: session.userId);
      state = AsyncData(
        current.copyWith(activeGroupId: _resolve(current.groups, groupId)),
      );
      ref.read(profileProvider.notifier).setActiveGroupLocally(groupId);
      AppHaptics.success();
      return null;
    } on AppFailure catch (failure) {
      return session.fail(failure, action);
    }
  }

  /// Leaves [groupId]. The server picks the next active group.
  Future<AppFailure?> leaveGroup(String groupId) =>
      _removeGroup(groupId, () => _repo.leaveGroup(groupId));

  /// Deletes [groupId] and all its data (admin only).
  Future<AppFailure?> deleteGroup(String groupId) =>
      _removeGroup(groupId, () => _repo.deleteGroup(groupId));

  /// Runs [action] and returns its failure, or null once the server did
  /// it. Reloading afterwards is separate: when only the reload fails the
  /// group is dropped locally, and the removal still counts as done.
  Future<AppFailure?> _removeGroup(
    String groupId,
    Future<Object?> Function() action,
  ) async {
    const what = 'a group removal';
    final session = guard();
    if (!session.holds(what)) return SessionGuard.dropped;
    try {
      await action();
    } on AppFailure catch (failure) {
      return session.fail(failure, what);
    }
    if (!session.holds(what)) return SessionGuard.dropped;
    AppHaptics.medium();
    try {
      await _reloadFromServer(session);
    } on AppFailure catch (failure) {
      if (!session.holds(what)) return SessionGuard.dropped;
      AppLogger.warn(
        'Groups did not reload after a membership change',
        failure,
      );
      _dropLocally(groupId, session);
    }
    return session.holds(what) ? null : SessionGuard.dropped;
  }

  /// Removes [groupId] from the loaded state; personal mode when it was
  /// the active group.
  void _dropLocally(String groupId, SessionGuard session) {
    if (!_applies(session, 'a local group removal')) return;
    final current = state.value;
    if (current == null) return;
    if (_serverScope == groupId) _serverScope = null;
    final wasActive = current.activeGroupId == groupId;
    state = AsyncData(
      current.copyWith(
        groups: current.groups.where((g) => g.id != groupId).toList(),
        activeGroupId: wasActive ? null : current.activeGroupId,
      ),
    );
    if (wasActive) {
      ref.read(profileProvider.notifier).setActiveGroupLocally(null);
    }
  }

  /// Re-reads groups and the server's active group after a membership
  /// change made on the server.
  Future<void> _reloadFromServer(SessionGuard session) async {
    const action = 'a groups reload';
    final userId = session.userId;
    if (userId == null || !session.holds(action)) return;
    final results = await Future.wait<Object?>([
      _repo.fetchMyGroups(),
      ref.read(profileRepositoryProvider).fetch(userId),
    ]);
    if (!_applies(session, action)) return;
    final groups = results[0]! as List<Group>;
    final saved = (results[1] as UserProfile?)?.activeGroupId;
    _serverScope = saved;
    final active = _resolve(groups, saved);
    state = AsyncData(
      GroupsState(groups: groups, activeGroupId: active, userId: userId),
    );
    ref.read(profileProvider.notifier).setActiveGroupLocally(active);
  }

  /// Membership changed elsewhere (transfer admin, approval): refresh.
  Future<void> membershipChanged() => refresh();
}

final groupsProvider =
    NotifierProvider<GroupsNotifier, AsyncValue<GroupsState>>(
      GroupsNotifier.new,
    );

/// The signed-in user's groups, or null while they load, after a failure,
/// or when the loaded groups are someone else's. Screens read this rather
/// than [groupsProvider]'s value.
final currentGroupsProvider = Provider<GroupsState?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  final value = ref.watch(groupsProvider).value;
  return userId != null && value?.userId == userId ? value : null;
});

/// Whether the signed-in user's groups have loaded (or failed to load),
/// so scope-dependent lists know whether to wait.
final groupsReadyProvider = Provider<bool>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  final groups = ref.watch(groupsProvider);
  if (groups.hasError && !groups.isLoading) return true;
  return groups.value?.userId == userId && !groups.isLoading;
});

/// The active group of the signed-in user, or null in personal mode, while
/// loading, or when the loaded groups belong to someone else.
final activeGroupProvider = Provider<Group?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  final value = ref.watch(groupsProvider).value;
  if (userId == null || value == null || value.userId != userId) return null;
  return value.activeGroup;
});
