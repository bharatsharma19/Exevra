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

  ExpenseState copyWith({
    List<Expense>? expenses,
    ExpenseFilter? filter,
    bool? isLoading,
    String? errorMessage,
    ExpenseGroup? currentGroup,
    List<GroupMember>? groupMembers,
  }) {
    return ExpenseState(
      expenses: expenses ?? this.expenses,
      filter: filter ?? this.filter,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
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
      AppHaptics.light();
      final auth = _ref.read(authNotifierProvider);
      final userId = auth.user?.id ?? 'demo-user-id';
      final groupId = isGroup ? auth.profile?.groupId : null;

      final newExpense = Expense(
        id: 'exp-${DateTime.now().millisecondsSinceEpoch}',
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

      final created = await _service.createExpense(newExpense);
      final updatedList = [created, ...state.expenses];
      state = state.copyWith(expenses: updatedList);
      AppHaptics.success();
      return true;
    } catch (e) {
      AppHaptics.error();
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> updateExpense(Expense updatedExpense) async {
    try {
      AppHaptics.light();
      final auth = _ref.read(authNotifierProvider);
      final currentUserId = auth.user?.id ?? 'demo-user-id';

      // Permission check: Any user who created an expense can edit it.
      if (!updatedExpense.canEdit(currentUserId) && currentUserId != 'demo-user-id') {
        throw Exception('Permission denied: You can only edit expenses you created.');
      }

      final saved = await _service.updateExpense(updatedExpense);
      final updatedList = state.expenses.map((e) => e.id == saved.id ? saved : e).toList();
      state = state.copyWith(expenses: updatedList);
      AppHaptics.success();
      return true;
    } catch (e) {
      AppHaptics.error();
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> deleteExpense(String expenseId) async {
    try {
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

      AppHaptics.light();
      await _service.deleteExpense(expenseId);
      final updatedList = state.expenses.where((e) => e.id != expenseId).toList();
      state = state.copyWith(expenses: updatedList);
      AppHaptics.medium();
      return true;
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
}

final expenseProvider = StateNotifierProvider<ExpenseNotifier, ExpenseState>((ref) {
  final service = ref.watch(supabaseServiceProvider);
  return ExpenseNotifier(service, ref);
});
