import 'dart:async';

import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/platform/connectivity.dart';
import 'package:expense_manager/core/platform/device_time_zone.dart';
import 'package:expense_manager/core/platform/share_service.dart';
import 'package:expense_manager/core/storage/preferences.dart';
import 'package:expense_manager/data/repositories/expense_repository.dart';
import 'package:expense_manager/data/repositories/group_repository.dart';
import 'package:expense_manager/data/repositories/insights_repository.dart';
import 'package:expense_manager/data/repositories/invitation_repository.dart';
import 'package:expense_manager/data/repositories/settlement_repository.dart';
import 'package:expense_manager/data/repositories/profile_repository.dart';
import 'package:expense_manager/models/balance.dart';
import 'package:expense_manager/models/expense.dart';
import 'package:expense_manager/models/group.dart';
import 'package:expense_manager/models/insights.dart';
import 'package:expense_manager/models/invitation.dart';
import 'package:expense_manager/models/money.dart';
import 'package:expense_manager/models/profile.dart';
import 'package:expense_manager/models/settlement.dart';
import 'package:expense_manager/providers/auth_provider.dart';
import 'package:expense_manager/services/auth_service.dart';
import 'package:expense_manager/core/router/deep_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

supabase.User fakeUser(String id, {bool verified = true}) => supabase.User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
  email: '$id@example.com',
  emailConfirmedAt: verified ? '2026-01-01T00:00:00Z' : null,
);

/// Auth with a controllable session and an event stream that, like
/// gotrue's, replays past events (starting with `initialSession`) to every
/// new listener.
class FakeAuthService implements AuthService {
  FakeAuthService({String? signedInAs, bool emitInitialSession = true}) {
    if (signedInAs != null) _user = fakeUser(signedInAs);
    if (emitInitialSession) emitInitial();
  }

  final List<supabase.AuthState> _history = [];
  final List<StreamController<supabase.AuthState>> _listeners = [];
  supabase.User? _user;
  int signOutCalls = 0;

  /// Outcome of the next [signUp].
  SignUpOutcome signUpOutcome = SignUpOutcome.confirmationSent;

  /// Thrown by the next email/password, code or password call.
  AppFailure? failNext;

  /// Users known to the fake "server" (email -> confirmed).
  final Map<String, bool> confirmedEmails = {};

  /// Result of the next Google / Apple sign-in (null = cancelled).
  String? googleUserId;
  AppleSignInResult? Function()? appleResult;

  final List<String> calls = [];

  supabase.Session _session(supabase.User user) => supabase.Session(
    accessToken: 'token-${user.id}-${_history.length}',
    tokenType: 'bearer',
    user: user,
  );

  void emit(supabase.AuthChangeEvent event, [supabase.User? user]) {
    final state = supabase.AuthState(
      event,
      user == null ? null : _session(user),
    );
    _history.add(state);
    for (final c in _listeners) {
      c.add(state);
    }
  }

  void emitInitial() => emit(supabase.AuthChangeEvent.initialSession, _user);

  AppFailure? _takeFailure() {
    final f = failNext;
    failNext = null;
    return f;
  }

  @override
  supabase.User? get currentUser => _user;

  @override
  supabase.Session? get currentSession =>
      _user == null ? null : _session(_user!);

  @override
  Stream<supabase.AuthState> get authStateChanges {
    late final StreamController<supabase.AuthState> controller;
    controller = StreamController<supabase.AuthState>(
      onCancel: () => _listeners.remove(controller),
    );
    _history.forEach(controller.add);
    _listeners.add(controller);
    return controller.stream;
  }

  /// The server signs [id] in (for example from another flow).
  void signInAs(String id, {bool verified = true}) {
    final user = fakeUser(id, verified: verified);
    _user = user;
    emit(supabase.AuthChangeEvent.signedIn, user);
  }

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    calls.add('signUp:$email');
    final f = _takeFailure();
    if (f != null) throw f;
    if (signUpOutcome == SignUpOutcome.signedIn) {
      signInAs(email.split('@').first);
    }
    return signUpOutcome;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    calls.add('signIn:$email');
    final f = _takeFailure();
    if (f != null) throw f;
    final confirmed = confirmedEmails[email.trim().toLowerCase()];
    if (confirmed == false) throw const AppFailure.emailNotConfirmed();
    signInAs(email.split('@').first);
  }

  @override
  Future<void> resendSignupConfirmation(String email) async {
    calls.add('resend:$email');
    final f = _takeFailure();
    if (f != null) throw f;
  }

  @override
  Future<void> verifySignupCode({
    required String email,
    required String code,
  }) async {
    calls.add('verifySignup:$code');
    final f = _takeFailure();
    if (f != null) throw f;
    signInAs(email.split('@').first);
  }

  @override
  Future<void> sendPasswordResetCode(String email) async {
    calls.add('sendReset:$email');
    final f = _takeFailure();
    if (f != null) throw f;
  }

  @override
  Future<String?> verifyRecoveryCode({
    required String email,
    required String code,
  }) async {
    calls.add('verifyRecovery:$code');
    final f = _takeFailure();
    if (f != null) throw f;
    final user = fakeUser(email.split('@').first);
    _user = user;
    emit(supabase.AuthChangeEvent.passwordRecovery, user);
    return currentSession?.accessToken;
  }

  /// Thrown by the next [updatePassword] (independent of [failNext]).
  AppFailure? failPasswordUpdate;

  @override
  Future<void> updatePassword(String newPassword) async {
    calls.add('updatePassword');
    final f = failPasswordUpdate;
    failPasswordUpdate = null;
    if (f != null) throw f;
    emit(supabase.AuthChangeEvent.userUpdated, _user);
  }

  /// The user [reloadUser] returns next (defaults to the current one).
  supabase.User? reloadedUser;

  @override
  Future<supabase.User?> reloadUser() async {
    calls.add('reloadUser');
    if (_user == null) return null;
    final user = reloadedUser ?? _user;
    _user = user;
    return user;
  }

  @override
  Future<bool> signInWithGoogle() async {
    calls.add('google');
    final f = _takeFailure();
    if (f != null) throw f;
    final id = googleUserId;
    if (id == null) return false;
    signInAs(id);
    return true;
  }

  @override
  Future<AppleSignInResult?> signInWithApple() async {
    calls.add('apple');
    final result = appleResult?.call();
    if (result?.user != null) {
      _user = result!.user;
      emit(supabase.AuthChangeEvent.signedIn, _user);
    }
    return result;
  }

  /// What [appleAuthorizationCode] returns (null: no Apple identity), or
  /// the failure it throws.
  String? appleCode;
  AppFailure? appleCodeFailure;

  @override
  Future<String?> appleAuthorizationCode() async {
    calls.add('appleCode');
    final f = appleCodeFailure;
    if (f != null) throw f;
    return appleCode;
  }

  @override
  Future<void> updateFullName(String fullName) async {
    calls.add('fullName:$fullName');
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _user = null;
    emit(supabase.AuthChangeEvent.signedOut);
  }
}

UserProfile profileOf(String id, {String? activeGroupId, String? locale}) =>
    UserProfile(
      id: id,
      displayName: 'User $id',
      email: '$id@example.com',
      activeGroupId: activeGroupId,
      locale: locale ?? 'en-IN',
      timezone: 'Asia/Kolkata',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

class FakeProfileRepository implements ProfileRepository {
  final Map<String, UserProfile> profiles = {};
  final List<(String, ProfileUpdate)> updates = [];
  AppFailure? failUpdates;
  AppFailure? failFetch;

  /// When set, updates wait for it before running.
  Completer<void>? holdUpdates;

  @override
  Future<UserProfile> fetch(String userId) async {
    final f = failFetch;
    if (f != null) throw f;
    final p = profiles[userId];
    if (p == null) throw const AppFailure.notFound(key: 'profile_not_found');
    return p;
  }

  @override
  Future<UserProfile> update(String userId, ProfileUpdate update) async {
    updates.add((userId, update));
    await holdUpdates?.future;
    final failure = failUpdates;
    if (failure != null) throw failure;
    final saved = (profiles[userId] ?? profileOf(userId)).apply(update);
    profiles[userId] = saved;
    return saved;
  }
}

Group groupOf(
  String id, {
  required String adminId,
  GroupRole role = GroupRole.admin,
  MemberStatus status = MemberStatus.approved,
  String currency = 'INR',
}) => Group(
  id: id,
  name: 'Group $id',
  currency: currency,
  adminId: adminId,
  createdAt: DateTime.utc(2026),
  role: role,
  status: status,
);

/// Groups per user; the "server" knows the caller from [currentUser].
class FakeGroupRepository implements GroupRepository {
  FakeGroupRepository(this.currentUser);

  final String? Function() currentUser;
  final Map<String, List<Group>> groupsByUser = {};
  final List<String?> activeGroupWrites = [];
  AppFailure? failSetActive;

  /// Group ids whose `set_active_group` call fails.
  final Set<String?> failSetActiveFor = {};

  /// The active group the server holds (the last successful write).
  String? serverActiveGroup;

  /// When non-empty, each fetch waits for the next completer and returns
  /// what it completes with.
  final List<Completer<List<Group>>> heldFetches = [];

  /// When non-empty, each `set_active_group` call waits for the next one.
  final List<Completer<void>> heldSetActive = [];

  @override
  Future<List<Group>> fetchMyGroups() async {
    if (heldFetches.isNotEmpty) return heldFetches.removeAt(0).future;
    return groupsByUser[currentUser()] ?? const [];
  }

  @override
  Future<void> setActiveGroup(String? groupId) async {
    if (heldSetActive.isNotEmpty) await heldSetActive.removeAt(0).future;
    activeGroupWrites.add(groupId);
    final failure = failSetActive;
    if (failure != null) throw failure;
    if (failSetActiveFor.contains(groupId)) {
      throw const AppFailure.network();
    }
    serverActiveGroup = groupId;
  }

  /// Members per group as `get_group_members` returns them.
  final Map<String, List<GroupMember>> membersByGroup = {};

  /// Members with an open balance (removal needs force).
  final Set<String> unsettled = {};
  final List<String> calls = [];
  int _ids = 0;

  @override
  Future<List<GroupMember>> fetchMembers(String groupId) async =>
      List.of(membersByGroup[groupId] ?? const []);

  void _updateMember(
    String groupId,
    String userId,
    GroupMember Function(GroupMember m) change,
  ) {
    final list = membersByGroup[groupId] ?? [];
    final i = list.indexWhere((m) => m.userId == userId);
    if (i < 0) throw const AppFailure.notFound(key: 'member_not_found');
    list[i] = change(list[i]);
  }

  @override
  Future<String> createGroup({
    required String name,
    required String currency,
  }) async {
    calls.add('create:$name:$currency');
    final user = currentUser()!;
    final id = 'new-${++_ids}';
    (groupsByUser[user] ??= []).insert(
      0,
      Group(
        id: id,
        name: name,
        currency: currency,
        adminId: user,
        createdAt: DateTime.utc(2026, 11),
        role: GroupRole.admin,
        status: MemberStatus.approved,
      ),
    );
    return id;
  }

  @override
  Future<JoinRequest> joinByCode(String code) async {
    calls.add('join:$code');
    if (code.toUpperCase().startsWith('BAD')) {
      throw const AppFailure.business('invalid_code');
    }
    final user = currentUser()!;
    (groupsByUser[user] ??= []).add(
      groupOf(
        'joined',
        adminId: 'someone',
        role: GroupRole.viewer,
        status: MemberStatus.pending,
      ),
    );
    return const JoinRequest(
      groupId: 'joined',
      groupName: 'Group joined',
      status: MemberStatus.pending,
    );
  }

  @override
  Future<void> approveMember(
    String groupId,
    String userId, {
    GroupRole role = GroupRole.member,
  }) async {
    calls.add('approve:$userId:${role.name}');
    _updateMember(
      groupId,
      userId,
      (m) => m.copyWith(role: role, status: MemberStatus.approved),
    );
  }

  @override
  Future<void> removeMember(
    String groupId,
    String userId, {
    bool force = false,
  }) async {
    calls.add('remove:$userId:$force');
    if (!force && unsettled.contains(userId)) {
      throw const AppFailure.business('outstanding_balance');
    }
    membersByGroup[groupId]?.removeWhere((m) => m.userId == userId);
  }

  @override
  Future<void> setMemberRole(
    String groupId,
    String userId,
    GroupRole role,
  ) async {
    calls.add('role:$userId:${role.name}');
    _updateMember(groupId, userId, (m) => m.copyWith(role: role));
  }

  @override
  Future<void> transferAdmin(String groupId, String newAdminId) async {
    calls.add('transfer:$newAdminId');
    final me = currentUser()!;
    _updateMember(
      groupId,
      newAdminId,
      (m) => m.copyWith(role: GroupRole.admin),
    );
    _updateMember(groupId, me, (m) => m.copyWith(role: GroupRole.member));
    final groups = groupsByUser[me] ?? [];
    final i = groups.indexWhere((g) => g.id == groupId);
    if (i >= 0) {
      groups[i] = groups[i].copyWith(
        role: GroupRole.member,
        adminId: newAdminId,
        inviteCode: null,
      );
    }
  }

  @override
  Future<LeaveResult> leaveGroup(String groupId) async {
    calls.add('leave:$groupId');
    final me = currentUser()!;
    if (unsettled.contains(me)) {
      throw const AppFailure.business('outstanding_balance');
    }
    groupsByUser[me]?.removeWhere((g) => g.id == groupId);
    return const LeaveResult(groupDeleted: false);
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    calls.add('delete:$groupId');
    groupsByUser[currentUser()]?.removeWhere((g) => g.id == groupId);
  }

  @override
  Future<InviteCode> rotateInviteCode(String groupId) async {
    calls.add('rotate:$groupId');
    return InviteCode('NEWC0DE0NEWC0DE0', DateTime.utc(2026, 12, 15));
  }
}

GroupMember memberOf(
  String userId, {
  GroupRole role = GroupRole.member,
  MemberStatus status = MemberStatus.approved,
  DateTime? joinedAt,
}) => GroupMember(
  userId: userId,
  displayName: 'User $userId',
  role: role,
  status: status,
  joinedAt: joinedAt ?? DateTime.utc(2026, 1, 1),
);

/// Records what would have been shared.
class FakeShareService implements ShareService {
  final List<String> shared = [];
  bool available = true;

  @override
  Future<bool> shareText(String text, {String? subject}) async {
    if (!available) return false;
    shared.add(text);
    return true;
  }
}

Expense expenseOf(
  String id, {
  required String userId,
  String? groupId,
  int amountMinor = 1000,
  DateTime? spentAt,
  String title = 'Lunch',
}) {
  final at = spentAt ?? DateTime.utc(2026, 11, 1);
  return Expense(
    id: id,
    userId: userId,
    groupId: groupId,
    title: title,
    amount: Money(amountMinor, 'INR'),
    category: 'Food',
    spentAt: at,
    createdAt: at,
    updatedAt: at,
  );
}

/// In-memory expenses with switches to fail writes or hold reads.
class FakeExpenseRepository implements ExpenseRepository {
  final List<Expense> rows = [];
  AppFailure? failWrites;
  AppFailure? failReads;

  /// Deleting one of these ids fails with permission denied.
  final Set<String> failDeleteIds = {};
  int fetchCalls = 0;
  final List<String> deleted = [];
  int _ids = 0;

  /// When set, each fetch waits for the next completer in this queue and
  /// returns what it completes with.
  final List<Completer<ExpensePage>> heldFetches = [];

  /// When set, create, update and delete wait for it before running.
  Completer<void>? holdWrites;

  bool _visible(String userId, ExpenseQuery query, Expense e) =>
      switch (query.scope) {
        PersonalScope() => e.isPersonal && e.userId == userId,
        GroupScope(:final groupId) => e.groupId == groupId,
        PersonalAndGroupScope(:final groupId) =>
          (e.isPersonal && e.userId == userId) || e.groupId == groupId,
      };

  @override
  Future<ExpensePage> fetchPage({
    required String userId,
    required ExpenseQuery query,
    ExpenseCursor? after,
    int limit = 30,
  }) async {
    fetchCalls++;
    if (heldFetches.isNotEmpty) return heldFetches.removeAt(0).future;
    final failure = failReads;
    if (failure != null) throw failure;
    final category = query.category;
    final search = query.search?.toLowerCase();
    var items =
        rows.where((e) => _visible(userId, query, e)).where((e) {
          if (category != null && e.category != category) return false;
          if (search != null && !e.title.toLowerCase().contains(search)) {
            return false;
          }
          return true;
        }).toList()..sort((a, b) {
          final t = b.spentAt.compareTo(a.spentAt);
          return t != 0 ? t : b.id.compareTo(a.id);
        });
    if (after != null) {
      // Keyset: rows strictly after the cursor in (spent_at, id) DESC.
      items = items.where((e) {
        final t = e.spentAt.compareTo(after.spentAt);
        return t < 0 || (t == 0 && e.id.compareTo(after.id) < 0);
      }).toList();
    }
    final page = items.take(limit).toList();
    final more = items.length > limit;
    return ExpensePage(page, more ? ExpenseCursor.after(page.last) : null);
  }

  @override
  Future<Expense> create(String userId, ExpenseDraft draft) async {
    await Future<void>.delayed(Duration.zero);
    await holdWrites?.future;
    final failure = failWrites;
    if (failure != null) throw failure;
    final saved = draft
        .toOptimistic(localId: 'srv-${++_ids}', userId: userId)
        .copyWith(isSyncing: false);
    rows.add(saved);
    return saved;
  }

  @override
  Future<Expense> update(Expense expense) async {
    await Future<void>.delayed(Duration.zero);
    await holdWrites?.future;
    final failure = failWrites;
    if (failure != null) throw failure;
    final saved = expense.copyWith(isSyncing: false);
    rows
      ..removeWhere((e) => e.id == expense.id)
      ..add(saved);
    return saved;
  }

  @override
  Future<void> delete(String expenseId) async {
    await Future<void>.delayed(Duration.zero);
    await holdWrites?.future;
    final failure = failWrites;
    if (failure != null) throw failure;
    if (failDeleteIds.contains(expenseId)) {
      throw const AppFailure.permissionDenied();
    }
    deleted.add(expenseId);
    rows.removeWhere((e) => e.id == expenseId);
  }

  /// Realtime changes pushed by the test (per group).
  final StreamController<GroupChange> realtime =
      StreamController<GroupChange>.broadcast();
  final List<String> watchedGroups = [];

  @override
  Stream<GroupChange> watchGroup(String groupId) {
    watchedGroups.add(groupId);
    return realtime.stream;
  }

  Future<void> closeRealtime() => realtime.close();
}

/// Server-computed insights per group (null key = personal scope).
class FakeInsightsRepository implements InsightsRepository {
  final Map<String?, ExpenseInsights> byGroup = {};
  AppFailure? failure;
  int calls = 0;

  @override
  Future<ExpenseInsights> fetch({
    required InsightScope scope,
    required InsightTimeframe timeframe,
    required String timeZone,
    required String preferredCurrency,
    String? groupId,
  }) async {
    calls++;
    final f = failure;
    if (f != null) throw f;
    return byGroup[groupId] ??
        ExpenseInsights.empty(
          scope: scope,
          timeframe: timeframe,
          currency: preferredCurrency,
        );
  }
}

GroupBalance balanceOf(String? userId, int netMinor, {String name = ''}) =>
    GroupBalance(
      userId: userId,
      displayName: name.isEmpty ? 'User $userId' : name,
      paid: Money(netMinor > 0 ? netMinor : 0, 'INR'),
      owed: Money(netMinor < 0 ? -netMinor : 0, 'INR'),
      settledOut: Money.zero('INR'),
      settledIn: Money.zero('INR'),
      net: Money(netMinor, 'INR'),
    );

/// Balances and suggestions per group, set by the test.
class FakeBalanceRepository implements BalanceRepository {
  final Map<String, List<GroupBalance>> balancesByGroup = {};
  final Map<String, List<SettleSuggestion>> suggestionsByGroup = {};

  @override
  Future<List<GroupBalance>> balances(String groupId) async =>
      balancesByGroup[groupId] ?? const [];

  @override
  Future<List<SettleSuggestion>> suggestions(String groupId) async =>
      suggestionsByGroup[groupId] ?? const [];
}

/// Settlements with the server's rules: the caller records as payer
/// (pending, at most [maxAmountMinor]), only the payee confirms, payer,
/// payee or [adminId] voids.
class FakeSettlementRepository implements SettlementRepository {
  FakeSettlementRepository(this.currentUser);

  final String? Function() currentUser;
  final List<Settlement> rows = [];
  final List<String> calls = [];

  /// Largest amount the caller may record (their remaining debt).
  int? maxAmountMinor;
  String? adminId;
  int _ids = 0;

  int listCalls = 0;
  int pendingCalls = 0;

  static int _newestFirst(Settlement a, Settlement b) {
    final t = b.createdAt.compareTo(a.createdAt);
    return t != 0 ? t : b.id.compareTo(a.id);
  }

  @override
  Future<List<Settlement>> list(
    String groupId, {
    Settlement? after,
    int limit = 50,
  }) async {
    listCalls++;
    final sorted = rows.where((s) => s.groupId == groupId).toList()
      ..sort(_newestFirst);
    final rest = after == null
        ? sorted
        : sorted.where((s) => _newestFirst(after, s) < 0).toList();
    return rest.take(limit).toList();
  }

  @override
  Future<List<Settlement>> pending(String groupId) async {
    pendingCalls++;
    return rows.where((s) => s.groupId == groupId && s.isPending).toList();
  }

  @override
  Future<List<SettlementEvent>> events(String settlementId) async => const [];

  @override
  Future<Settlement> record({
    required String groupId,
    required String toUser,
    required Money amount,
    String? note,
  }) async {
    calls.add('record:$toUser:${amount.amountMinor}');
    final max = maxAmountMinor;
    if (max != null && amount.amountMinor > max) {
      throw const AppFailure.business('settlement_exceeds_debt');
    }
    final saved = Settlement(
      id: 's${++_ids}',
      groupId: groupId,
      fromUser: currentUser(),
      toUser: toUser,
      amount: amount,
      status: SettlementStatus.pending,
      note: note,
      createdBy: currentUser(),
      createdAt: DateTime.utc(2026, 11, 10).add(Duration(minutes: _ids)),
    );
    rows.add(saved);
    return saved;
  }

  Settlement _find(String id) => rows.firstWhere(
    (s) => s.id == id,
    orElse: () => throw const AppFailure.notFound(key: 'settlement_not_found'),
  );

  void _replace(Settlement updated) {
    final i = rows.indexWhere((s) => s.id == updated.id);
    rows[i] = updated;
  }

  @override
  Future<Settlement> confirm(String settlementId) async {
    calls.add('confirm:$settlementId');
    final s = _find(settlementId);
    if (s.toUser != currentUser()) {
      throw const AppFailure.permissionDenied(key: 'not_settlement_payee');
    }
    if (!s.isPending) {
      throw const AppFailure.business('settlement_not_pending');
    }
    final updated = s.copyWith(
      status: SettlementStatus.confirmed,
      confirmedAt: DateTime.utc(2026, 11, 11),
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<Settlement> voidSettlement(
    String settlementId, {
    String? reason,
  }) async {
    calls.add('void:$settlementId:${reason ?? ''}');
    final s = _find(settlementId);
    final me = currentUser();
    if (me != s.fromUser && me != s.toUser && me != adminId) {
      throw const AppFailure.permissionDenied(key: 'not_settlement_party');
    }
    if (s.isVoided) {
      throw const AppFailure.business('settlement_already_voided');
    }
    final updated = s.copyWith(
      status: SettlementStatus.voided,
      voidedAt: DateTime.utc(2026, 11, 12),
      voidedBy: me,
      voidReason: reason,
    );
    _replace(updated);
    return updated;
  }
}

/// Email invitations; [nextSend] decides whether the email "went out".
class FakeInvitationRepository implements InvitationRepository {
  final List<GroupInvitation> pending = [];
  final List<String> sentTo = [];
  final List<String> revoked = [];
  SentInvitation nextSend = const SentInvitation(
    invitationId: 'inv-1',
    sent: true,
  );
  AppFailure? failSend;

  @override
  Future<SentInvitation> send({
    required String groupId,
    required String email,
    GroupRole role = GroupRole.member,
  }) async {
    final f = failSend;
    if (f != null) throw f;
    sentTo.add(email);
    pending.add(
      GroupInvitation(
        id: nextSend.invitationId,
        groupId: groupId,
        inviterId: 'admin',
        email: email,
        role: role,
        status: InvitationStatus.pending,
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
        createdAt: DateTime.now().toUtc(),
      ),
    );
    return nextSend;
  }

  @override
  Future<List<GroupInvitation>> listPending(String groupId) async =>
      pending.where((i) => i.groupId == groupId).toList();

  @override
  Future<void> revoke(String invitationId) async {
    revoked.add(invitationId);
    pending.removeWhere((i) => i.id == invitationId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Network state controlled by the test.
class FakeConnectivitySource implements ConnectivitySource {
  FakeConnectivitySource({this.online = true});

  bool online;
  final StreamController<bool> controller = StreamController<bool>.broadcast();

  void set(bool value) {
    online = value;
    controller.add(value);
  }

  @override
  Future<bool> isOnline() async => online;

  @override
  Stream<bool> get changes => controller.stream;
}

/// Everything a signed-in session needs, backed by fakes.
class TestBackend {
  TestBackend({String? signedInAs})
    : auth = FakeAuthService(signedInAs: signedInAs) {
    groups = FakeGroupRepository(() => auth.currentUser?.id);
    settlements = FakeSettlementRepository(() => auth.currentUser?.id);
  }

  final FakeAuthService auth;
  final FakeProfileRepository profiles = FakeProfileRepository();
  late final FakeGroupRepository groups;
  final FakeExpenseRepository expenses = FakeExpenseRepository();
  final FakeInsightsRepository insights = FakeInsightsRepository();
  final FakeBalanceRepository balances = FakeBalanceRepository();
  late final FakeSettlementRepository settlements;
  final FakeConnectivitySource connectivity = FakeConnectivitySource();

  final FakeShareService share = FakeShareService();

  /// Set before [container] to fake email invitations.
  FakeInvitationRepository? invitations;

  /// Incoming links (set before [container] to simulate a cold start).
  FakeLinkSource links = FakeLinkSource();

  Future<ProviderContainer> container({
    Map<String, Object> prefs = const {},
    List<Override> extraOverrides = const [],
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authServiceProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profiles),
        groupRepositoryProvider.overrideWithValue(groups),
        expenseRepositoryProvider.overrideWithValue(expenses),
        insightsRepositoryProvider.overrideWithValue(insights),
        balanceRepositoryProvider.overrideWithValue(balances),
        settlementRepositoryProvider.overrideWithValue(settlements),
        connectivitySourceProvider.overrideWithValue(connectivity),
        shareServiceProvider.overrideWithValue(share),
        if (invitations case final invitations?)
          invitationRepositoryProvider.overrideWithValue(invitations),
        deviceTimeZoneProvider.overrideWith((ref) async => 'Asia/Kolkata'),
        linkSourceProvider.overrideWithValue(links),
        ...extraOverrides,
      ],
    );
    // Deliver the replayed initial auth event (microtasks only, so this
    // also works inside testWidgets' fake async zone).
    container.read(authControllerProvider);
    for (var i = 0; i < 10; i++) {
      await Future<void>.microtask(() {});
    }
    return container;
  }
}

/// Lets queued microtasks and zero-delay timers run.
Future<void> settle([int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Incoming links pushed by the test.
class FakeLinkSource implements LinkSource {
  FakeLinkSource({this.initial});

  final Uri? initial;
  final StreamController<Uri> controller = StreamController<Uri>.broadcast();

  @override
  Future<Uri?> initialLink() async => initial;

  @override
  Stream<Uri> get links => controller.stream;

  Future<void> close() => controller.close();
}
