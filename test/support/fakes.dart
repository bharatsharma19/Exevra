import 'dart:async';

import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/platform/device_time_zone.dart';
import 'package:expense_manager/core/storage/preferences.dart';
import 'package:expense_manager/data/repositories/expense_repository.dart';
import 'package:expense_manager/data/repositories/group_repository.dart';
import 'package:expense_manager/data/repositories/profile_repository.dart';
import 'package:expense_manager/models/expense.dart';
import 'package:expense_manager/models/group.dart';
import 'package:expense_manager/models/money.dart';
import 'package:expense_manager/models/profile.dart';
import 'package:expense_manager/providers/auth_provider.dart';
import 'package:expense_manager/services/auth_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Auth with a controllable session and event stream.
class FakeAuthService implements AuthService {
  FakeAuthService({String? signedInAs}) {
    if (signedInAs != null) _user = fakeUser(signedInAs);
  }

  final _events = StreamController<supabase.AuthState>.broadcast();
  supabase.User? _user;
  int signOutCalls = 0;

  @override
  supabase.User? get currentUser => _user;

  @override
  supabase.Session? get currentSession => null;

  @override
  bool get isAuthenticated => _user != null;

  @override
  Stream<supabase.AuthState> get authStateChanges => _events.stream;

  void signIn(String id) {
    final user = fakeUser(id);
    _user = user;
    _events.add(
      supabase.AuthState(
        supabase.AuthChangeEvent.signedIn,
        supabase.Session(accessToken: 't', tokenType: 'bearer', user: user),
      ),
    );
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _user = null;
    _events.add(
      const supabase.AuthState(supabase.AuthChangeEvent.signedOut, null),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
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

  @override
  Future<UserProfile> fetch(String userId) async {
    final p = profiles[userId];
    if (p == null) throw const AppFailure.notFound(key: 'profile_not_found');
    return p;
  }

  @override
  Future<UserProfile> update(String userId, ProfileUpdate update) async {
    updates.add((userId, update));
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

  @override
  Future<List<Group>> fetchMyGroups() async =>
      groupsByUser[currentUser()] ?? const [];

  @override
  Future<void> setActiveGroup(String? groupId) async {
    activeGroupWrites.add(groupId);
    final failure = failSetActive;
    if (failure != null) throw failure;
  }

  @override
  Future<List<GroupMember>> fetchMembers(String groupId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
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
  int fetchCalls = 0;
  int _ids = 0;

  /// When set, each fetch waits for the next completer in this queue and
  /// returns what it completes with.
  final List<Completer<ExpensePage>> heldFetches = [];

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
    final items = rows.where((e) => _visible(userId, query, e)).toList()
      ..sort((a, b) {
        final t = b.spentAt.compareTo(a.spentAt);
        return t != 0 ? t : b.id.compareTo(a.id);
      });
    return ExpensePage(items.take(limit).toList(), null);
  }

  @override
  Future<Expense> create(String userId, ExpenseDraft draft) async {
    await Future<void>.delayed(Duration.zero);
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
    final failure = failWrites;
    if (failure != null) throw failure;
    rows.removeWhere((e) => e.id == expenseId);
  }

  @override
  Stream<GroupChangeKind> watchGroup(String groupId) => const Stream.empty();
}

/// Everything a signed-in session needs, backed by fakes.
class TestBackend {
  TestBackend({String? signedInAs})
    : auth = FakeAuthService(signedInAs: signedInAs) {
    groups = FakeGroupRepository(() => auth.currentUser?.id);
  }

  final FakeAuthService auth;
  final FakeProfileRepository profiles = FakeProfileRepository();
  late final FakeGroupRepository groups;
  final FakeExpenseRepository expenses = FakeExpenseRepository();

  Future<ProviderContainer> container({
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final preferences = await SharedPreferences.getInstance();
    return ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authServiceProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profiles),
        groupRepositoryProvider.overrideWithValue(groups),
        expenseRepositoryProvider.overrideWithValue(expenses),
        deviceTimeZoneProvider.overrideWith((ref) async => 'Asia/Kolkata'),
      ],
    );
  }
}

/// Lets queued microtasks and zero-delay timers run.
Future<void> settle([int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
