import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/expense_model.dart';
import '../models/group_model.dart';
import '../services/supabase_service.dart';
import '../core/utils/haptics.dart';
import 'auth_provider.dart';

enum ExpenseTypeFilter { all, personal, group }

class ExpenseFilter {
  final ExpenseTypeFilter type;
  final String category;
  final String searchQuery;

  const ExpenseFilter({
    this.type = ExpenseTypeFilter.all,
    this.category = 'All',
    this.searchQuery = '',
  });

  ExpenseFilter copyWith({
    ExpenseTypeFilter? type,
    String? category,
    String? searchQuery,
  }) {
    return ExpenseFilter(
      type: type ?? this.type,
      category: category ?? this.category,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

class ExpenseState {
  final List<Expense> expenses;
  final ExpenseFilter filter;
  final bool isLoading;
  final String? errorMessage;
  final ExpenseGroup? currentGroup;
  final List<GroupMember> groupMembers;
  final List<ExpenseGroup> userGroups;
  final List<Settlement> settlementHistory;
  final List<GroupInvitation> pendingInvitations;

  const ExpenseState({
    this.expenses = const [],
    this.filter = const ExpenseFilter(),
    this.isLoading = false,
    this.errorMessage,
    this.currentGroup,
    this.groupMembers = const [],
    this.userGroups = const [],
    this.settlementHistory = const [],
    this.pendingInvitations = const [],
  });

  List<Expense> get filteredExpenses {
    return expenses.where((item) {
      // Type filter
      if (filter.type == ExpenseTypeFilter.personal && !item.isPersonal) {
        return false;
      }
      if (filter.type == ExpenseTypeFilter.group && item.isPersonal) {
        return false;
      }
      // Category filter
      if (filter.category != 'All' &&
          item.category.toLowerCase() != filter.category.toLowerCase()) {
        return false;
      }
      // Search query
      if (filter.searchQuery.isNotEmpty) {
        final query = filter.searchQuery.toLowerCase();
        final matchesTitle = item.title.toLowerCase().contains(query);
        final matchesCategory = item.category.toLowerCase().contains(query);
        final matchesNotes = item.notes?.toLowerCase().contains(query) ?? false;
        if (!matchesTitle && !matchesCategory && !matchesNotes) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  double get totalSpent => expenses.fold(0.0, (sum, e) => sum + e.amount);

  double get personalSpent => expenses
      .where((e) => e.isPersonal)
      .fold(0.0, (sum, e) => sum + e.amount);

  double get groupSpent => expenses
      .where((e) => !e.isPersonal)
      .fold(0.0, (sum, e) => sum + e.amount);

  /// Computes the actual out-of-pocket money spent by the current user:
  /// all personal and group expenses where the current user is the payer.
  double userTotalOutflow(String? currentUserId) {
    if (currentUserId == null) return totalSpent;
    return expenses
        .where((e) => e.userId == currentUserId)
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  double userPersonalSpent(String? currentUserId) {
    if (currentUserId == null) return personalSpent;
    return expenses
        .where((e) => e.isPersonal && e.userId == currentUserId)
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  double userGroupSpent(String? currentUserId) {
    if (currentUserId == null) return groupSpent;
    return expenses
        .where((e) => !e.isPersonal && e.userId == currentUserId)
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  bool canUserAddGroupExpenses(String? userId) {
    if (userId == null || currentGroup == null) return false;
    if (currentGroup!.adminId == userId) return true;
    final member = groupMembers.where((m) => m.userId == userId).firstOrNull;
    if (member == null) return false;
    return member.canAddExpenses;
  }

  bool isUserViewerOnly(String? userId) {
    if (userId == null || currentGroup == null) return false;
    if (currentGroup!.adminId == userId) return false;
    final member = groupMembers.where((m) => m.userId == userId).firstOrNull;
    return member?.isViewerOnly ?? false;
  }

  List<GroupMember> get pendingReviewMembers =>
      groupMembers.where((m) => m.isViewerOnly).toList();

  /// Calculates dynamic debts among all group members using integer-cent math,
  /// remainder distribution, recorded settlement offsets, and greedy minimization.
  List<SettlementDebt> get settlements {
    if (currentGroup == null || groupMembers.length < 2) return [];

    final groupExpenses = expenses.where((e) => !e.isPersonal).toList();
    if (groupExpenses.isEmpty && settlementHistory.isEmpty) return [];

    final memberNameMap = <String, String>{
      for (final m in groupMembers)
        m.userId: (m.displayName != null && m.displayName!.trim().isNotEmpty)
            ? m.displayName!.trim()
            : 'Member',
    };

    // Initialize balance in integer cents for each member
    final balancesInCents = <String, int>{
      for (final m in groupMembers) m.userId: 0,
    };

    // 1. Credit payers with their out-of-pocket payment
    int totalGroupCents = 0;
    for (final expense in groupExpenses) {
      final cents = (expense.amount * 100).round();
      final payer = expense.userId;
      balancesInCents[payer] = (balancesInCents[payer] ?? 0) + cents;
      totalGroupCents += cents;
    }

    // 2. Deduct fair share evenly across all members with fair remainder distribution
    final memberCount = groupMembers.length;
    if (memberCount > 0 && totalGroupCents > 0) {
      final fairShareCents = totalGroupCents ~/ memberCount;
      final remainderCents = totalGroupCents % memberCount;

      for (var idx = 0; idx < memberCount; idx++) {
        final userId = groupMembers[idx].userId;
        final share = fairShareCents + (idx < remainderCents ? 1 : 0);
        balancesInCents[userId] = (balancesInCents[userId] ?? 0) - share;
      }
    }

    // 3. Adjust balances with recorded settlements (payer credited, receiver debited)
    for (final settlement in settlementHistory) {
      final sCents = (settlement.amount * 100).round();
      balancesInCents[settlement.payerId] =
          (balancesInCents[settlement.payerId] ?? 0) + sCents;
      balancesInCents[settlement.payeeId] =
          (balancesInCents[settlement.payeeId] ?? 0) - sCents;
    }

    // 4. Partition into debtors and creditors
    final debtors = <String, int>{};
    final creditors = <String, int>{};

    balancesInCents.forEach((userId, balanceCents) {
      if (balanceCents < 0) {
        debtors[userId] = -balanceCents;
      } else if (balanceCents > 0) {
        creditors[userId] = balanceCents;
      }
    });

    // 5. Greedily match largest debtor with largest creditor to minimize transactions
    final debtorKeys = debtors.keys.toList()
      ..sort((a, b) => debtors[b]!.compareTo(debtors[a]!));
    final creditorKeys = creditors.keys.toList()
      ..sort((a, b) => creditors[b]!.compareTo(creditors[a]!));

    final List<SettlementDebt> debts = [];
    int dIdx = 0;
    int cIdx = 0;

    while (dIdx < debtorKeys.length && cIdx < creditorKeys.length) {
      final debtor = debtorKeys[dIdx];
      final creditor = creditorKeys[cIdx];

      final dCents = debtors[debtor]!;
      final cCents = creditors[creditor]!;
      final minCents = (dCents < cCents) ? dCents : cCents;

      if (minCents > 0) {
        debts.add(
          SettlementDebt(
            fromUserId: debtor,
            toUserId: creditor,
            amount: minCents / 100.0,
            fromUserName: memberNameMap[debtor] ?? 'Member',
            toUserName: memberNameMap[creditor] ?? 'Member',
          ),
        );
      }

      debtors[debtor] = dCents - minCents;
      creditors[creditor] = cCents - minCents;

      if (debtors[debtor]! <= 0) dIdx++;
      if (creditors[creditor]! <= 0) cIdx++;
    }

    return debts;
  }

  ExpenseState copyWith({
    List<Expense>? expenses,
    ExpenseFilter? filter,
    bool? isLoading,
    Object? errorMessage = const Object(),
    ExpenseGroup? currentGroup,
    List<GroupMember>? groupMembers,
    List<ExpenseGroup>? userGroups,
    List<Settlement>? settlementHistory,
    List<GroupInvitation>? pendingInvitations,
  }) {
    return ExpenseState(
      expenses: expenses ?? this.expenses,
      filter: filter ?? this.filter,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage == const Object()
          ? this.errorMessage
          : errorMessage as String?,
      currentGroup: currentGroup ?? this.currentGroup,
      groupMembers: groupMembers ?? this.groupMembers,
      userGroups: userGroups ?? this.userGroups,
      settlementHistory: settlementHistory ?? this.settlementHistory,
      pendingInvitations: pendingInvitations ?? this.pendingInvitations,
    );
  }
}

class ExpenseNotifier extends StateNotifier<ExpenseState> {
  final SupabaseService _service;
  final Ref _ref;

  ExpenseNotifier(this._service, this._ref) : super(const ExpenseState()) {
    loadAll();
  }

  Future<void> loadAll({String? preferredGroupId}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final authState = _ref.read(authNotifierProvider);

      // 1. Fetch all groups the current user belongs to
      final userGroups = await _service.fetchUserGroups();

      // 2. Determine active group ID
      String? activeGroupId;
      if (preferredGroupId != null &&
          userGroups.any((g) => g.id == preferredGroupId)) {
        activeGroupId = preferredGroupId;
      } else if (authState.profile?.groupId != null &&
          userGroups.any((g) => g.id == authState.profile!.groupId)) {
        activeGroupId = authState.profile!.groupId;
      } else if (userGroups.isNotEmpty) {
        activeGroupId = userGroups.first.id;
      }

      // 3. Keep profile synchronized if active group changed
      if (activeGroupId != authState.profile?.groupId) {
        _ref.read(authNotifierProvider.notifier).setActiveGroupId(activeGroupId);
      }

      // 4. Fetch expenses: includes both user's personal expenses and active group's expenses
      final expenses = await _service.fetchExpenses(groupId: activeGroupId);

      ExpenseGroup? group;
      List<GroupMember> members = [];
      List<GroupInvitation> invitations = [];
      List<Settlement> settlements = [];

      if (activeGroupId != null) {
        group = await _service.fetchGroup(activeGroupId);
        members = await _service.fetchGroupMembers(activeGroupId);
        invitations = await _service.fetchGroupInvitations(activeGroupId);
        settlements = await _service.fetchSettlements(activeGroupId);
      }

      state = state.copyWith(
        expenses: expenses,
        currentGroup: group,
        groupMembers: members,
        userGroups: userGroups,
        pendingInvitations: invitations,
        settlementHistory: settlements,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  void setFilter(ExpenseFilter filter) {
    AppHaptics.selection();
    state = state.copyWith(filter: filter);
  }

  void setCategoryFilter(String category) {
    AppHaptics.selection();
    state = state.copyWith(filter: state.filter.copyWith(category: category));
  }

  void setTypeFilter(ExpenseTypeFilter type) {
    AppHaptics.selection();
    state = state.copyWith(filter: state.filter.copyWith(type: type));
  }

  void setSearchQuery(String query) {
    state = state.copyWith(filter: state.filter.copyWith(searchQuery: query));
  }

  // ---------------------------------------------------------------------------
  // CRUD ACTIONS
  // ---------------------------------------------------------------------------

  Future<bool> createExpense({
    required String title,
    required double amount,
    required String category,
    required DateTime date,
    String? notes,
    bool isGroup = false,
  }) async {
    try {
      state = state.copyWith(errorMessage: null);
      AppHaptics.light();
      final auth = _ref.read(authNotifierProvider);
      final userId = auth.user?.id ?? 'demo-user-id';
      final groupId = isGroup ? (state.currentGroup?.id ?? auth.profile?.groupId) : null;

      final newExpense = Expense(
        id: 'opt-${DateTime.now().millisecondsSinceEpoch}',
        userId: userId,
        groupId: groupId,
        title: title.trim(),
        amount: amount,
        category: category,
        date: date,
        notes: notes?.trim(),
        isPersonal: groupId == null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        creatorName: auth.profile?.displayName ?? 'You',
      );

      final previousExpenses = state.expenses;
      state = state.copyWith(expenses: [newExpense, ...state.expenses]);
      AppHaptics.success();

      try {
        final created = await _service.createExpense(newExpense);
        final updatedList = state.expenses
            .map((e) => e.id == newExpense.id ? created : e)
            .toList();
        state = state.copyWith(expenses: updatedList);
        return true;
      } catch (e) {
        state = state.copyWith(
          expenses: previousExpenses,
          errorMessage: e.toString(),
        );
        AppHaptics.error();
        return false;
      }
    } catch (e) {
      AppHaptics.error();
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> updateExpense(Expense updatedExpense) async {
    try {
      state = state.copyWith(errorMessage: null);
      AppHaptics.light();
      final auth = _ref.read(authNotifierProvider);
      final currentUserId = auth.user?.id ?? 'demo-user-id';

      if (!updatedExpense.canEdit(currentUserId) && currentUserId != 'demo-user-id') {
        throw Exception('Permission denied: You can only edit expenses you created.');
      }

      final previousExpenses = state.expenses;
      final optimisticList = state.expenses
          .map((e) => e.id == updatedExpense.id ? updatedExpense : e)
          .toList();
      state = state.copyWith(expenses: optimisticList);
      AppHaptics.success();

      try {
        final saved = await _service.updateExpense(updatedExpense);
        final finalUpdatedList = state.expenses
            .map((e) => e.id == saved.id ? saved : e)
            .toList();
        state = state.copyWith(expenses: finalUpdatedList);
        return true;
      } catch (e) {
        state = state.copyWith(
          expenses: previousExpenses,
          errorMessage: e.toString(),
        );
        AppHaptics.error();
        return false;
      }
    } catch (e) {
      AppHaptics.error();
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> deleteExpense(String expenseId) async {
    try {
      state = state.copyWith(errorMessage: null);
      final expense = state.expenses.firstWhere((e) => e.id == expenseId);
      final auth = _ref.read(authNotifierProvider);
      final currentUserId = auth.user?.id ?? 'demo-user-id';
      final isGroupAdmin = state.currentGroup?.isAdmin(currentUserId) ?? true;

      if (!expense.canDelete(currentUserId, isGroupAdmin) &&
          currentUserId != 'demo-user-id') {
        throw Exception(
          expense.isPersonal
              ? 'Permission denied: Only the creator can delete personal expenses.'
              : 'Permission denied: Group expenses can ONLY be deleted by the Group Admin.',
        );
      }

      final previousExpenses = state.expenses;
      final optimisticList =
          state.expenses.where((e) => e.id != expenseId).toList();
      state = state.copyWith(expenses: optimisticList);
      AppHaptics.medium();

      try {
        await _service.deleteExpense(expenseId);
        return true;
      } catch (e) {
        state = state.copyWith(
          expenses: previousExpenses,
          errorMessage: e.toString(),
        );
        AppHaptics.error();
        return false;
      }
    } catch (e) {
      AppHaptics.error();
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // MULTI-GROUP MANAGEMENT
  // ---------------------------------------------------------------------------

  Future<void> switchGroup(String? groupId) async {
    try {
      state = state.copyWith(isLoading: true, errorMessage: null);
      AppHaptics.selection();
      await _service.switchActiveGroup(groupId);
      await _ref.read(authNotifierProvider.notifier).setActiveGroupId(groupId);
      await loadAll(preferredGroupId: groupId);
      AppHaptics.success();
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      AppHaptics.error();
    }
  }

  Future<bool> createGroup(String name) async {
    try {
      state = state.copyWith(errorMessage: null);
      AppHaptics.light();
      final group = await _service.createGroup(name);
      await _ref.read(authNotifierProvider.notifier).setActiveGroupId(group.id);
      await loadAll(preferredGroupId: group.id);
      AppHaptics.success();
      return true;
    } catch (e) {
      AppHaptics.error();
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> joinGroup(String inviteCode) async {
    try {
      state = state.copyWith(errorMessage: null);
      AppHaptics.light();
      final group = await _service.joinGroupByInvite(inviteCode);
      if (group != null) {
        await _ref.read(authNotifierProvider.notifier).setActiveGroupId(group.id);
        await loadAll(preferredGroupId: group.id);
        AppHaptics.success();
        return true;
      } else {
        throw Exception('Invalid or expired group invite code');
      }
    } catch (e) {
      AppHaptics.error();
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> acceptInvitation(String token) async {
    try {
      state = state.copyWith(errorMessage: null);
      AppHaptics.light();
      final group = await _service.acceptGroupInvitation(token);
      if (group != null) {
        await _ref.read(authNotifierProvider.notifier).setActiveGroupId(group.id);
        await loadAll(preferredGroupId: group.id);
        AppHaptics.success();
        return true;
      } else {
        throw Exception('Unable to accept invitation. It may be expired or already used.');
      }
    } catch (e) {
      AppHaptics.error();
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> inviteMemberByEmail({
    required String email,
    String role = 'member',
  }) async {
    final group = state.currentGroup;
    if (group == null) return false;

    try {
      state = state.copyWith(errorMessage: null);
      AppHaptics.light();
      final auth = _ref.read(authNotifierProvider);
      final inviterName = auth.profile?.displayName ?? 'A group member';

      final invite = await _service.createGroupInvitation(
        groupId: group.id,
        email: email.trim(),
        role: role,
      );

      if (invite != null) {
        await _service.sendGroupInviteEmail(
          invitation: invite,
          inviteCode: group.inviteCode,
          inviterName: inviterName,
        );
        final currentInvites = [
          invite,
          ...state.pendingInvitations.where((i) => i.id != invite.id),
        ];
        state = state.copyWith(pendingInvitations: currentInvites);
        AppHaptics.success();
        return true;
      }
      return false;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to send invite: $e');
      AppHaptics.error();
      return false;
    }
  }

  Future<bool> revokeInvitation(String invitationId) async {
    try {
      state = state.copyWith(errorMessage: null);
      AppHaptics.medium();
      final ok = await _service.revokeGroupInvitation(invitationId);
      if (ok) {
        state = state.copyWith(
          pendingInvitations: state.pendingInvitations
              .where((i) => i.id != invitationId)
              .toList(),
        );
        AppHaptics.success();
        return true;
      }
      return false;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to revoke invite: $e');
      AppHaptics.error();
      return false;
    }
  }

  Future<bool> recordSettlement({
    required String toUserId,
    required double amount,
    String? notes,
  }) async {
    final group = state.currentGroup;
    if (group == null) return false;

    try {
      state = state.copyWith(errorMessage: null);
      AppHaptics.light();
      final settlement = await _service.recordSettlement(
        groupId: group.id,
        payeeId: toUserId,
        amount: amount,
        notes: notes,
      );

      final updatedHistory = [settlement, ...state.settlementHistory];
      state = state.copyWith(settlementHistory: updatedHistory);
      AppHaptics.success();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to record payment: $e');
      AppHaptics.error();
      return false;
    }
  }

  Future<void> leaveGroup() async {
    if (state.currentGroup == null) return;
    try {
      state = state.copyWith(errorMessage: null);
      AppHaptics.light();
      final groupId = state.currentGroup!.id;
      await _service.leaveGroup(groupId);
      await _ref.read(authNotifierProvider.notifier).setActiveGroupId(null);
      await loadAll();
      AppHaptics.medium();
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<void> deleteGroup() async {
    if (state.currentGroup == null) return;
    try {
      state = state.copyWith(errorMessage: null);
      AppHaptics.heavy();
      final groupId = state.currentGroup!.id;
      await _service.deleteGroup(groupId);
      await _ref.read(authNotifierProvider.notifier).setActiveGroupId(null);
      await loadAll();
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<bool> approveGroupMember(String memberUserId) async {
    final group = state.currentGroup;
    if (group == null) return false;
    try {
      state = state.copyWith(errorMessage: null);
      AppHaptics.light();
      final ok = await _service.approveGroupMember(group.id, memberUserId);
      if (ok) {
        state = state.copyWith(
          groupMembers: state.groupMembers.map((m) {
            if (m.userId == memberUserId) {
              return m.copyWith(role: 'member');
            }
            return m;
          }).toList(),
        );
        AppHaptics.success();
        return true;
      }
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to approve member: $e');
      AppHaptics.error();
    }
    return false;
  }

  Future<bool> removeGroupMember(String memberUserId) async {
    final group = state.currentGroup;
    if (group == null) return false;
    try {
      state = state.copyWith(errorMessage: null);
      AppHaptics.light();
      final ok = await _service.removeGroupMember(group.id, memberUserId);
      if (ok) {
        state = state.copyWith(
          groupMembers: state.groupMembers
              .where((m) => m.userId != memberUserId)
              .toList(),
        );
        AppHaptics.medium();
        return true;
      }
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to remove member: $e');
      AppHaptics.error();
    }
    return false;
  }
}

final expenseProvider =
    StateNotifierProvider<ExpenseNotifier, ExpenseState>((ref) {
  final service = ref.watch(supabaseServiceProvider);
  return ExpenseNotifier(service, ref);
});
