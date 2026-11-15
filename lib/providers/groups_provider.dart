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
import 'failure_reporter.dart';
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

  /// The server refused it; nothing was created.
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

  /// Whether a result requested for [userId] may still be applied: the
  /// notifier is reused across sign-ins, so after an await the signed-in
  /// user (and the loaded state) may belong to someone else.
  bool _isFor(String? userId) {
    if (!ref.mounted || userId == null) return false;
    if (ref.read(currentUserIdProvider) != userId) return false;
    final owner = state.value?.userId;
    return owner == null || owner == userId;
  }

  /// The saved active group if it is still an approved membership.
  static String? _resolve(List<Group> groups, String? saved) {
    if (saved == null) return null;
    final match = groups.where((g) => g.id == saved && g.isApproved);
    return match.isEmpty ? null : saved;
  }

  void _report(AppFailure failure, {bool report = true}) {
    if (report && ref.mounted) {
      ref.read(failureReporterProvider.notifier).report(failure);
    }
    AppHaptics.error();
  }

  /// Re-reads the group list, keeping the active scope when still valid.
  /// With [report] false a failure is only returned.
  Future<AppFailure?> refresh({bool report = true}) async {
    final userId = ref.read(currentUserIdProvider);
    try {
      final groups = await _repo.fetchMyGroups();
      if (!_isFor(userId)) return null;
      final active = state.value?.activeGroupId;
      state = AsyncData(
        GroupsState(
          groups: groups,
          activeGroupId: _resolve(groups, active),
          userId: userId,
        ),
      );
      return null;
    } on AppFailure catch (failure) {
      if (!_isFor(userId)) return null;
      _report(failure, report: report);
      return failure;
    }
  }

  /// Switches to [groupId] (null = personal). Writes the profile once per
  /// switch. Writes are sent in order, and when the latest switch fails
  /// the scope the server holds is shown again. With [report] false a
  /// failure is only returned.
  Future<AppFailure?> switchScope(String? groupId, {bool report = true}) async {
    final current = state.value;
    final userId = current?.userId;
    if (current == null || userId == null) return null;
    if (current.activeGroupId == groupId) return null;
    AppHaptics.selection();
    final number = ++_scopeSwitches;
    state = AsyncData(current.copyWith(activeGroupId: groupId));
    final write = _scopeWrites.then((_) => _repo.setActiveGroup(groupId));
    _scopeWrites = write.then<void>((_) {}, onError: (Object _) {});
    try {
      await write;
      if (!_isFor(userId)) return null;
      _serverScope = groupId;
      if (number == _scopeSwitches) {
        ref.read(profileProvider.notifier).setActiveGroupLocally(groupId);
      }
      return null;
    } on AppFailure catch (failure) {
      if (!_isFor(userId)) return null;
      // A later switch decides the scope (and reports its own failure).
      if (number != _scopeSwitches) return failure;
      final now = state.value ?? current;
      final restored = _resolve(now.groups, _serverScope);
      state = AsyncData(now.copyWith(activeGroupId: restored));
      ref.read(profileProvider.notifier).setActiveGroupLocally(restored);
      _report(failure, report: report);
      return failure;
    }
  }

  /// Creates a group and makes it active. With [report] false failures
  /// are only returned (for a form that shows them itself).
  ///
  /// Once the server returned the new id the group exists, so a failure
  /// to reload or open it is never reported as a failure to create (a
  /// retry would make a second group). A request that failed on the way
  /// may also have created it: the list is reloaded and the result says
  /// so instead of inviting a retry.
  Future<GroupCreateResult> createGroup(
    String name, {
    required String currency,
    bool report = true,
  }) async {
    final String id;
    try {
      id = await _repo.createGroup(name: name, currency: currency);
    } on AppFailure catch (failure) {
      if (failure.outcomeUnknown) {
        await refresh(report: false);
        const unconfirmed = AppFailure.network(key: 'group_unconfirmed');
        _report(unconfirmed, report: report);
        return const GroupCreateResult(
          GroupCreateStatus.unconfirmed,
          failure: unconfirmed,
        );
      }
      _report(failure, report: report);
      return GroupCreateResult(GroupCreateStatus.failed, failure: failure);
    }
    // Opening needs the group in the list; without it the scope would
    // point at a group this device cannot show.
    final problem =
        await refresh(report: report) ?? await switchScope(id, report: report);
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
    try {
      final request = await _repo.joinByCode(code);
      await refresh();
      AppHaptics.success();
      return (request, null);
    } on AppFailure catch (failure) {
      _report(failure, report: report);
      return (null, failure);
    }
  }

  /// Issues a new invite code for [groupId] (admin only); the old code
  /// stops working.
  Future<(InviteCode?, AppFailure?)> rotateInviteCode(String groupId) async {
    try {
      final code = await _repo.rotateInviteCode(groupId);
      await refresh();
      AppHaptics.success();
      return (code, null);
    } on AppFailure catch (failure) {
      _report(failure);
      return (null, failure);
    }
  }

  /// Accepts an email invitation; the server makes that group active.
  Future<AppFailure?> acceptInvitation(String token) async {
    final userId = ref.read(currentUserIdProvider);
    try {
      final groupId = await ref
          .read(invitationRepositoryProvider)
          .accept(token);
      await refresh();
      if (!_isFor(userId)) return null;
      _serverScope = groupId;
      final current = state.value ?? GroupsState(userId: userId);
      state = AsyncData(
        current.copyWith(activeGroupId: _resolve(current.groups, groupId)),
      );
      ref.read(profileProvider.notifier).setActiveGroupLocally(groupId);
      AppHaptics.success();
      return null;
    } on AppFailure catch (failure) {
      if (!_isFor(userId)) return null;
      _report(failure);
      return failure;
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
    final userId = ref.read(currentUserIdProvider);
    try {
      await action();
    } on AppFailure catch (failure) {
      if (!_isFor(userId)) return null;
      _report(failure);
      return failure;
    }
    AppHaptics.medium();
    try {
      await _reloadFromServer();
    } on AppFailure catch (failure) {
      AppLogger.warn(
        'Groups did not reload after a membership change',
        failure,
      );
      _dropLocally(groupId, userId);
    }
    return null;
  }

  /// Removes [groupId] from the loaded state; personal mode when it was
  /// the active group.
  void _dropLocally(String groupId, String? userId) {
    if (!_isFor(userId)) return;
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
  Future<void> _reloadFromServer() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    final results = await Future.wait<Object?>([
      _repo.fetchMyGroups(),
      ref.read(profileRepositoryProvider).fetch(userId),
    ]);
    if (!_isFor(userId)) return;
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
