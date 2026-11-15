import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_failure.dart';
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

/// Groups of the signed-in user plus the active scope (personal or one
/// group). The scope is stored on the server with `set_active_group`, and
/// each switch writes exactly once.
class GroupsNotifier extends AsyncNotifier<GroupsState> {
  GroupRepository get _repo => ref.read(groupRepositoryProvider);

  /// Number of the latest scope switch; only the latest one updates or
  /// rolls back the visible scope.
  int _scopeSwitches = 0;

  /// Scope writes run one after another so the server ends on the last.
  Future<void> _scopeWrites = Future.value();

  /// The active group the server holds as far as this device knows.
  String? _serverScope;

  @override
  Future<GroupsState> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const GroupsState();
    final repo = ref.watch(groupRepositoryProvider);

    final results = await Future.wait<Object?>([
      repo.fetchMyGroups(),
      ref.read(profileProvider.future),
    ]);
    final groups = results[0]! as List<Group>;
    final saved = (results[1] as UserProfile?)?.activeGroupId;
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
  Future<AppFailure?> refresh() async {
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
      _report(failure);
      return failure;
    }
  }

  /// Switches to [groupId] (null = personal). Writes the profile once per
  /// switch. Writes are sent in order, and when the latest switch fails
  /// the scope the server holds is shown again.
  Future<AppFailure?> switchScope(String? groupId) async {
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
      _report(failure);
      return failure;
    }
  }

  /// Creates a group and makes it active. Returns the failure or null.
  /// With [report] false a failure to create is only returned (for a form
  /// that shows it inline).
  Future<AppFailure?> createGroup(
    String name, {
    required String currency,
    bool report = true,
  }) async {
    try {
      final id = await _repo.createGroup(name: name, currency: currency);
      final refreshed = await refresh();
      if (refreshed != null) return refreshed;
      final switched = await switchScope(id);
      if (switched == null) AppHaptics.success();
      return switched;
    } on AppFailure catch (failure) {
      _report(failure, report: report);
      return failure;
    }
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
      _removeGroup(() => _repo.leaveGroup(groupId));

  /// Deletes [groupId] and all its data (admin only).
  Future<AppFailure?> deleteGroup(String groupId) =>
      _removeGroup(() => _repo.deleteGroup(groupId));

  Future<AppFailure?> _removeGroup(Future<Object?> Function() action) async {
    try {
      await action();
      await _reloadFromServer();
      AppHaptics.medium();
      return null;
    } on AppFailure catch (failure) {
      _report(failure);
      return failure;
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

final groupsProvider = AsyncNotifierProvider<GroupsNotifier, GroupsState>(
  GroupsNotifier.new,
);

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
