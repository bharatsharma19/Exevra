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

  const ExpenseState({
    this.expenses = const [],
    this.filter = const ExpenseFilter(),
    this.isLoading = false,
    this.errorMessage,
    this.currentGroup,
    this.groupMembers = const [],
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
      if (filter.category != 'All' && item.category.toLowerCase() != filter.category.toLowerCase()) {
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

  List<SettlementDebt> get settlements {
    if (currentGroup == null || groupMembers.isEmpty) return [];

    final groupExpenses = expenses.where((e) => !e.isPersonal).toList();
    if (groupExpenses.isEmpty) return [];

    double totalSpent = 0.0;
    final balances = <String, double>{};
    for (var m in groupMembers) {
      balances[m.userId] = 0.0;
    }

    for (var expense in groupExpenses) {
      final amount = expense.amount;
      final payer = expense.userId;
      if (!balances.containsKey(payer)) {
        balances[payer] = 0.0;
      }
      balances[payer] = balances[payer]! + amount;
      totalSpent += amount;
    }

    final memberCount = groupMembers.length;
    int totalCents = (totalSpent * 100).round();
    int splitCents = totalCents ~/ memberCount;
    int remainder = totalCents % memberCount;

    for (var i = 0; i < memberCount; i++) {
      final m = groupMembers[i].userId;
      int toDeduct = splitCents + (i < remainder ? 1 : 0);
      balances[m] = balances[m]! - (toDeduct / 100.0);
    }

    final debtors = <String, double>{};
    final creditors = <String, double>{};

    balances.forEach((userId, balance) {
      final b = double.parse(balance.toStringAsFixed(2));
      if (b < 0) {
        debtors[userId] = -b;
      } else if (b > 0) {
        creditors[userId] = b;
      }
    });

    final List<SettlementDebt> debts = [];
    final debtorKeys = debtors.keys.toList();
    final creditorKeys = creditors.keys.toList();

    int i = 0, j = 0;
    while (i < debtorKeys.length && j < creditorKeys.length) {
      final debtor = debtorKeys[i];
      final creditor = creditorKeys[j];

      final dAmount = debtors[debtor]!;
      final cAmount = creditors[creditor]!;

      final min = (dAmount < cAmount) ? dAmount : cAmount;

      if (min > 0) {
        debts.add(SettlementDebt(fromUserId: debtor, toUserId: creditor, amount: min));
      }

      debtors[debtor] = double.parse((dAmount - min).toStringAsFixed(2));
      creditors[creditor] = double.parse((cAmount - min).toStringAsFixed(2));

      if (debtors[debtor]! <= 0) i++;
      if (creditors[creditor]! <= 0) j++;
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
  }) {
    return ExpenseState(
      expenses: expenses ?? this.expenses,
      filter: filter ?? this.filter,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage == const Object() ? this.errorMessage : errorMessage as String?,
      currentGroup: currentGroup ?? this.currentGroup,
      groupMembers: groupMembers ?? this.groupMembers,
    );
  }
}

class ExpenseNotifier extends StateNotifier<ExpenseState> {
  final SupabaseService _service;
  final Ref _ref;

  ExpenseNotifier(this._service, this._ref) : super(const ExpenseState()) {
    loadAll();
  }

  Future<void> loadAll() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      state = state.copyWith(errorMessage: null);
      final authState = _ref.read(authNotifierProvider);
      final groupId = authState.profile?.groupId;

      final expenses = await _service.fetchExpenses(groupId: groupId);

      ExpenseGroup? group;
      List<GroupMember> members = [];
      if (groupId != null) {
        group = await _service.fetchGroup(groupId);
        members = await _service.fetchGroupMembers(groupId);
      }

      state = state.copyWith(
        expenses: expenses,
        currentGroup: group,
        groupMembers: members,
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
      final groupId = isGroup ? auth.profile?.groupId : null;

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
        final updatedList = state.expenses.map((e) => e.id == newExpense.id ? created : e).toList();
        state = state.copyWith(expenses: updatedList);
        return true;
      } catch (e) {
        state = state.copyWith(expenses: previousExpenses, errorMessage: e.toString());
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

      // Permission check: Any user who created an expense can edit it.
      if (!updatedExpense.canEdit(currentUserId) && currentUserId != 'demo-user-id') {
        throw Exception('Permission denied: You can only edit expenses you created.');
      }

      final previousExpenses = state.expenses;
      final optimisticList = state.expenses.map((e) => e.id == updatedExpense.id ? updatedExpense : e).toList();
      state = state.copyWith(expenses: optimisticList);
      AppHaptics.success();

      try {
        final saved = await _service.updateExpense(updatedExpense);
        final finalUpdatedList = state.expenses.map((e) => e.id == saved.id ? saved : e).toList();
        state = state.copyWith(expenses: finalUpdatedList);
        return true;
      } catch (e) {
        state = state.copyWith(expenses: previousExpenses, errorMessage: e.toString());
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

      // Permission check:
      // Personal: creator only
      // Group: Group Admin ONLY
      if (!expense.canDelete(currentUserId, isGroupAdmin) && currentUserId != 'demo-user-id') {
        throw Exception(
          expense.isPersonal
              ? 'Permission denied: Only the creator can delete personal expenses.'
              : 'Permission denied: Group expenses can ONLY be deleted by the Group Admin.',
        );
      }

      final previousExpenses = state.expenses;
      final optimisticList = state.expenses.where((e) => e.id != expenseId).toList();
      state = state.copyWith(expenses: optimisticList);
      AppHaptics.medium();

      try {
        await _service.deleteExpense(expenseId);
        return true;
      } catch (e) {
        state = state.copyWith(expenses: previousExpenses, errorMessage: e.toString());
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
  // GROUP MANAGEMENT
  // ---------------------------------------------------------------------------

  Future<bool> createGroup(String name) async {
    try {
      state = state.copyWith(errorMessage: null);
      AppHaptics.light();
      final group = await _service.createGroup(name);
      state = state.copyWith(
        currentGroup: group,
        groupMembers: [
          GroupMember(
            id: 'mem-admin',
            groupId: group.id,
            userId: group.adminId,
            role: 'admin',
            displayName: _ref.read(authNotifierProvider).profile?.displayName ?? 'You',
            joinedAt: DateTime.now(),
          )
        ],
      );
      await loadAll();
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
        state = state.copyWith(currentGroup: group);
        await loadAll();
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

  Future<void> leaveGroup() async {
    if (state.currentGroup == null) return;
    try {
      state = state.copyWith(errorMessage: null);
      AppHaptics.light();
      await _service.leaveGroup(state.currentGroup!.id);
      state = state.copyWith(currentGroup: null, groupMembers: const []);
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
      await _service.deleteGroup(state.currentGroup!.id);
      state = state.copyWith(currentGroup: null, groupMembers: const []);
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
          groupMembers: state.groupMembers.where((m) => m.userId != memberUserId).toList(),
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

final expenseProvider = StateNotifierProvider<ExpenseNotifier, ExpenseState>((ref) {
  final service = ref.watch(supabaseServiceProvider);
  return ExpenseNotifier(service, ref);
});
