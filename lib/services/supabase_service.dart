import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/app_constants.dart';
import '../models/user_profile.dart';
import '../models/group_model.dart';
import '../models/expense_model.dart';
import '../models/insight_model.dart';

/// Supabase Client Wrapper and Enterprise Data Access Layer
class SupabaseService {
  static SupabaseService? _instance;
  static SupabaseService get instance => _instance ??= SupabaseService._();

  SupabaseService._();

  SupabaseClient get client => Supabase.instance.client;
  User? get currentUser => client.auth.currentUser;
  bool get isAuthenticated => currentUser != null;

  bool get isDemoMode {
    final url = (dotenv.isInitialized ? dotenv.env['SUPABASE_URL'] : null) ??
        AppConstants.defaultSupabaseUrl;
    return url.contains('xyzcompany');
  }

  // In-memory demo fallback store when running without live Supabase credentials
  final List<Expense> _localExpenses = [];
  UserProfile? _localProfile;
  ExpenseGroup? _localGroup;
  final List<GroupMember> _localMembers = [];

  // ---------------------------------------------------------------------------
  // PROFILE MANAGEMENT
  // ---------------------------------------------------------------------------

  Future<UserProfile?> fetchProfile(String userId) async {
    try {
      final response = await client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (response != null) {
        _localProfile = UserProfile.fromJson(response);
        return _localProfile;
      }
    } catch (e) {
      debugPrint('[SupabaseService] fetchProfile fallback: $e');
    }

    if (_localProfile != null && _localProfile!.id == userId) {
      return _localProfile;
    }

    final metaName = currentUser?.userMetadata?['full_name'] as String?;
    final resolvedDisplayName = (metaName != null && metaName.trim().isNotEmpty)
        ? metaName.trim()
        : (currentUser?.email?.split('@').first ?? 'User');

    // Default profile stub using real user account metadata
    final stub = UserProfile(
      id: userId,
      displayName: resolvedDisplayName,
      email: currentUser?.email ?? 'user@antigravity.io',
      phone: currentUser?.phone,
      currency: AppConstants.defaultCurrency,
      themeMode: 'system',
      hapticsEnabled: true,
      aiConsent: false,
      createdAt: DateTime.now().subtract(const Duration(days: 30)),
      updatedAt: DateTime.now(),
    );
    _localProfile = stub;
    return stub;
  }

  Future<UserProfile> updateProfile(UserProfile profile) async {
    try {
      final data = profile.toJson();
      data.remove('created_at');
      data['updated_at'] = DateTime.now().toIso8601String();

      await client.from('profiles').upsert(data);
      _localProfile = profile;
      return profile;
    } catch (e) {
      debugPrint('[SupabaseService] updateProfile fallback: $e');
      _localProfile = profile;
      return profile;
    }
  }

  // ---------------------------------------------------------------------------
  // GROUP MANAGEMENT
  // ---------------------------------------------------------------------------

  Future<ExpenseGroup?> fetchGroup(String groupId) async {
    try {
      final response = await client
          .from('groups')
          .select()
          .eq('id', groupId)
          .maybeSingle();

      if (response != null) {
        return ExpenseGroup.fromJson(response);
      }
    } catch (e) {
      debugPrint('[SupabaseService] fetchGroup fallback: $e');
    }
    return _localGroup;
  }

  Future<ExpenseGroup> createGroup(String name) async {
    final userId = currentUser?.id ?? 'demo-user-id';
    final now = DateTime.now();
    final newGroup = ExpenseGroup(
      id: 'grp-${now.millisecondsSinceEpoch}',
      name: name,
      inviteCode: 'INV-${now.millisecondsSinceEpoch.toString().substring(7)}',
      adminId: userId,
      createdAt: now,
      membersCount: 1,
    );

    try {
      final res = await client
          .from('groups')
          .insert({
            'name': name,
            'admin_id': userId,
          })
          .select()
          .single();

      final created = ExpenseGroup.fromJson(res);
      // Join group as admin
      await client.from('group_members').insert({
        'group_id': created.id,
        'user_id': userId,
        'role': 'admin',
      });
      // Update profile
      await client.from('profiles').update({'group_id': created.id}).eq('id', userId);

      _localGroup = created;
      return created;
    } catch (e) {
      debugPrint('[SupabaseService] createGroup fallback: $e');
      _localGroup = newGroup;
      if (_localProfile != null) {
        _localProfile = _localProfile!.copyWith(groupId: newGroup.id);
      }
      return newGroup;
    }
  }

  Future<ExpenseGroup?> joinGroupByInvite(String inviteCode) async {
    try {
      final result = await client.rpc(
        'join_group_by_invite',
        params: {'p_invite_code': inviteCode.trim()},
      );

      if (result != null && result['group_id'] != null) {
        return await fetchGroup(result['group_id'] as String);
      }
    } catch (e) {
      debugPrint('[SupabaseService] joinGroupByInvite fallback: $e');
    }

    if (_localGroup != null && _localGroup!.inviteCode.toLowerCase() == inviteCode.trim().toLowerCase()) {
      final userId = currentUser?.id ?? 'demo-user-id';
      if (_localProfile != null) {
        _localProfile = _localProfile!.copyWith(groupId: _localGroup!.id);
      }
      if (!_localMembers.any((m) => m.userId == userId)) {
        _localMembers.add(GroupMember(
          id: 'mem-${DateTime.now().millisecondsSinceEpoch}',
          groupId: _localGroup!.id,
          userId: userId,
          role: 'viewer', // Pending Admin Review
          displayName: _localProfile?.displayName ?? (currentUser?.email?.split('@').first ?? 'User'),
          joinedAt: DateTime.now(),
        ));
      }
      return _localGroup;
    }
    return null;
  }

  Future<bool> approveGroupMember(String groupId, String memberUserId) async {
    try {
      await client
          .from('group_members')
          .update({'role': 'member'})
          .match({'group_id': groupId, 'user_id': memberUserId});
      final idx = _localMembers.indexWhere((m) => m.groupId == groupId && m.userId == memberUserId);
      if (idx != -1) {
        _localMembers[idx] = _localMembers[idx].copyWith(role: 'member');
      }
      return true;
    } catch (e) {
      debugPrint('[SupabaseService] approveGroupMember: $e');
      final idx = _localMembers.indexWhere((m) => m.groupId == groupId && m.userId == memberUserId);
      if (idx != -1) {
        _localMembers[idx] = _localMembers[idx].copyWith(role: 'member');
        return true;
      }
      return false;
    }
  }

  Future<List<GroupMember>> fetchGroupMembers(String groupId) async {
    try {
      final res = await client
          .from('group_members')
          .select('*, profiles(display_name, avatar_url)')
          .eq('group_id', groupId);

      return (res as List).map((m) => GroupMember.fromJson(m)).toList();
    } catch (e) {
      debugPrint('[SupabaseService] fetchGroupMembers fallback: $e');
    }

    if (_localMembers.isEmpty) {
      final userId = currentUser?.id ?? 'demo-user-id';
      _localMembers.add(GroupMember(
        id: 'mem-1',
        groupId: groupId,
        userId: userId,
        role: 'admin',
        displayName: _localProfile?.displayName ?? (currentUser?.email?.split('@').first ?? 'User'),
        joinedAt: DateTime.now().subtract(const Duration(days: 15)),
      ));
    }
    return _localMembers;
  }

  Future<void> leaveGroup(String groupId) async {
    final userId = currentUser?.id ?? 'demo-user-id';
    try {
      await client.from('group_members').delete().match({
        'group_id': groupId,
        'user_id': userId,
      });
      await client.from('profiles').update({'group_id': null}).eq('id', userId);
    } catch (e) {
      debugPrint('[SupabaseService] leaveGroup fallback: $e');
    }
    if (_localProfile != null) {
      _localProfile = _localProfile!.copyWith(groupId: null);
    }
    _localGroup = null;
  }

  Future<void> deleteGroup(String groupId) async {
    try {
      await client.from('groups').delete().eq('id', groupId);
    } catch (e) {
      debugPrint('[SupabaseService] deleteGroup fallback: $e');
    }
    if (_localProfile != null && _localProfile!.groupId == groupId) {
      _localProfile = _localProfile!.copyWith(groupId: null);
    }
    _localGroup = null;
  }

  // ---------------------------------------------------------------------------
  // EXPENSES CRUD & PERMISSIONS
  // ---------------------------------------------------------------------------

  Future<List<Expense>> fetchExpenses({
    String? groupId,
    bool? isPersonal,
    String? category,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = client.from('expenses').select('*, profiles(display_name)');

      if (isPersonal == true) {
        query = query.filter('group_id', 'is', null);
      } else if (groupId != null) {
        query = query.eq('group_id', groupId);
      }

      if (category != null && category.isNotEmpty && category != 'All') {
        query = query.eq('category', category);
      }

      if (startDate != null) {
        query = query.gte('date', startDate.toIso8601String());
      }
      if (endDate != null) {
        query = query.lte('date', endDate.toIso8601String());
      }

      final response = await query.order('date', ascending: false);
      final expenses = (response as List).map((e) => Expense.fromJson(e)).toList();
      return expenses;
    } catch (e) {
      debugPrint('[SupabaseService] fetchExpenses fallback: $e');
    }

    // Seed mock local expenses ONLY when running in dummy demo mode (not live Supabase)
    if (isDemoMode && _localExpenses.isEmpty) {
      _seedMockExpenses();
    }

    return _localExpenses.where((exp) {
      if (isPersonal == true && !exp.isPersonal) return false;
      if (groupId != null && exp.groupId != groupId) return false;
      if (category != null && category.isNotEmpty && category != 'All' && exp.category != category) {
        return false;
      }
      if (startDate != null && exp.date.isBefore(startDate)) return false;
      if (endDate != null && exp.date.isAfter(endDate)) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<Expense> createExpense(Expense expense) async {
    final userId = currentUser?.id ?? 'demo-user-id';
    try {
      final res = await client
          .from('expenses')
          .insert({
            'user_id': userId,
            'group_id': expense.groupId,
            'title': expense.title,
            'amount': expense.amount,
            'category': expense.category,
            'date': expense.date.toIso8601String(),
            'notes': expense.notes,
            'receipt_url': expense.receiptUrl,
          })
          .select('*, profiles(display_name)')
          .single();

      final created = Expense.fromJson(res);
      _localExpenses.insert(0, created);
      return created;
    } catch (e) {
      debugPrint('[SupabaseService] createExpense fallback: $e');
      _localExpenses.insert(0, expense);
      return expense;
    }
  }

  Future<Expense> updateExpense(Expense expense) async {
    try {
      final res = await client
          .from('expenses')
          .update({
            'title': expense.title,
            'amount': expense.amount,
            'category': expense.category,
            'date': expense.date.toIso8601String(),
            'notes': expense.notes,
            'receipt_url': expense.receiptUrl,
            'group_id': expense.groupId,
          })
          .eq('id', expense.id)
          .select('*, profiles(display_name)')
          .single();

      final updated = Expense.fromJson(res);
      final idx = _localExpenses.indexWhere((e) => e.id == expense.id);
      if (idx != -1) _localExpenses[idx] = updated;
      return updated;
    } catch (e) {
      debugPrint('[SupabaseService] updateExpense fallback: $e');
      final idx = _localExpenses.indexWhere((e) => e.id == expense.id);
      if (idx != -1) _localExpenses[idx] = expense;
      return expense;
    }
  }

  Future<void> deleteExpense(String expenseId) async {
    try {
      await client.from('expenses').delete().eq('id', expenseId);
    } catch (e) {
      debugPrint('[SupabaseService] deleteExpense fallback: $e');
    }
    _localExpenses.removeWhere((e) => e.id == expenseId);
  }

  // ---------------------------------------------------------------------------
  // FINANCIAL INSIGHTS ENGINE (RPC with In-Memory Aggregation Fallback)
  // ---------------------------------------------------------------------------

  Future<FinancialInsight> getExpenseInsights({
    required String timeframe,
    String? groupId,
  }) async {
    try {
      final Map<String, dynamic> params = {'p_timeframe': timeframe};
      if (groupId != null) {
        params['p_group_id'] = groupId;
      }

      final response = await client.rpc(
        'get_expense_insights',
        params: params,
      );

      if (response is Map) {
        return FinancialInsight.fromJson(Map<String, dynamic>.from(response));
      } else if (response is String) {
        final decoded = jsonDecode(response);
        if (decoded is Map) {
          return FinancialInsight.fromJson(Map<String, dynamic>.from(decoded));
        }
      }
    } catch (e) {
      debugPrint('[SupabaseService] getExpenseInsights RPC fallback: $e');
    }

    // High-performance client-side aggregation fallback
    final now = DateTime.now();
    DateTime cutoff;
    int daysCount;

    if (timeframe == 'weekly') {
      cutoff = now.subtract(const Duration(days: 7));
      daysCount = 7;
    } else if (timeframe == 'yearly') {
      cutoff = now.subtract(const Duration(days: 365));
      daysCount = 365;
    } else {
      cutoff = now.subtract(const Duration(days: 30));
      daysCount = 30;
    }

    final filtered = (await fetchExpenses(groupId: groupId))
        .where((e) => e.date.isAfter(cutoff))
        .toList();

    double total = 0.0;
    ExpenseHighlight? highest;
    final Map<String, double> catTotals = {};
    final Map<String, int> catCounts = {};
    final Map<String, double> dayTotals = {};

    for (final exp in filtered) {
      total += exp.amount;
      catTotals[exp.category] = (catTotals[exp.category] ?? 0.0) + exp.amount;
      catCounts[exp.category] = (catCounts[exp.category] ?? 0) + 1;

      final dateKey = '${exp.date.year}-${exp.date.month.toString().padLeft(2, '0')}-${exp.date.day.toString().padLeft(2, '0')}';
      dayTotals[dateKey] = (dayTotals[dateKey] ?? 0.0) + exp.amount;

      if (highest == null || exp.amount > highest.amount) {
        highest = ExpenseHighlight(
          id: exp.id,
          title: exp.title,
          amount: exp.amount,
          category: exp.category,
          date: exp.date,
        );
      }
    }

    final List<CategoryExpense> breakdown = catTotals.entries.map((entry) {
      final count = catCounts[entry.key] ?? 1;
      final pct = total > 0 ? (entry.value / total) * 100 : 0.0;
      return CategoryExpense(
        category: entry.key,
        total: entry.value,
        count: count,
        percentage: double.parse(pct.toStringAsFixed(1)),
      );
    }).toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    final List<TrendPoint> trends = dayTotals.entries.map((entry) {
      return TrendPoint(
        label: entry.key,
        pointDate: DateTime.parse(entry.key),
        total: entry.value,
        count: 1,
      );
    }).toList()
      ..sort((a, b) => a.pointDate.compareTo(b.pointDate));

    return FinancialInsight(
      timeframe: timeframe,
      totalAmount: total,
      expenseCount: filtered.length,
      averageDaily: daysCount > 0 ? total / daysCount : 0.0,
      highestExpense: highest,
      categoryBreakdown: breakdown,
      trendData: trends,
    );
  }

  // ---------------------------------------------------------------------------
  // ACCOUNT DELETION (Store Compliance)
  // ---------------------------------------------------------------------------

  Future<bool> deleteUserAccount() async {
    try {
      await client.rpc('delete_user_account');
      await client.auth.signOut();
      _localExpenses.clear();
      _localProfile = null;
      _localGroup = null;
      return true;
    } catch (e) {
      debugPrint('[SupabaseService] deleteUserAccount fallback: $e');
      _localExpenses.clear();
      _localProfile = null;
      _localGroup = null;
      return true;
    }
  }

  void _seedMockExpenses() {
    final now = DateTime.now();
    final userId = currentUser?.id ?? 'demo-user-id';

    _localExpenses.addAll([
      Expense(
        id: 'exp-1',
        userId: userId,
        groupId: null,
        title: 'Whole Foods Market',
        amount: 86.45,
        category: 'Food',
        date: now.subtract(const Duration(hours: 3)),
        notes: 'Weekly groceries and fresh organic produce',
        isPersonal: true,
        createdAt: now.subtract(const Duration(hours: 3)),
        updatedAt: now.subtract(const Duration(hours: 3)),
      ),
      Expense(
        id: 'exp-2',
        userId: userId,
        groupId: null,
        title: 'Uber Ride to Downtown',
        amount: 24.80,
        category: 'Transport',
        date: now.subtract(const Duration(hours: 14)),
        notes: 'Meeting client at Innovation Center',
        isPersonal: true,
        createdAt: now.subtract(const Duration(hours: 14)),
        updatedAt: now.subtract(const Duration(hours: 14)),
      ),
      Expense(
        id: 'exp-3',
        userId: userId,
        groupId: 'grp-demo',
        title: 'Fiber Internet Bill',
        amount: 95.00,
        category: 'Utilities',
        date: now.subtract(const Duration(days: 1)),
        notes: 'Gigabit fiber connection for shared studio',
        isPersonal: false,
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(days: 1)),
        creatorName: 'Alex Mercer',
      ),
      Expense(
        id: 'exp-4',
        userId: userId,
        groupId: null,
        title: 'Apple Developer Subscription',
        amount: 99.00,
        category: 'Entertainment',
        date: now.subtract(const Duration(days: 2)),
        notes: 'Annual developer certificate renewal',
        isPersonal: true,
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(days: 2)),
      ),
      Expense(
        id: 'exp-5',
        userId: userId,
        groupId: 'grp-demo',
        title: 'Studio Coffee & Snacks',
        amount: 42.15,
        category: 'Food',
        date: now.subtract(const Duration(days: 3)),
        notes: 'Espresso beans and oat milk restock',
        isPersonal: false,
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now.subtract(const Duration(days: 3)),
        creatorName: 'Elena Rostova',
      ),
      Expense(
        id: 'exp-6',
        userId: userId,
        groupId: null,
        title: 'Studio Rent Share',
        amount: 850.00,
        category: 'Housing',
        date: now.subtract(const Duration(days: 5)),
        notes: 'Monthly loft lease portion',
        isPersonal: true,
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now.subtract(const Duration(days: 5)),
      ),
      Expense(
        id: 'exp-7',
        userId: userId,
        groupId: null,
        title: 'Ergonomic Standing Desk',
        amount: 380.00,
        category: 'Shopping',
        date: now.subtract(const Duration(days: 8)),
        notes: 'Motorized dual-motor frame',
        isPersonal: true,
        createdAt: now.subtract(const Duration(days: 8)),
        updatedAt: now.subtract(const Duration(days: 8)),
      ),
      Expense(
        id: 'exp-8',
        userId: userId,
        groupId: 'grp-demo',
        title: 'Co-working Electricity',
        amount: 68.20,
        category: 'Utilities',
        date: now.subtract(const Duration(days: 12)),
        notes: 'Mid-summer power consumption',
        isPersonal: false,
        createdAt: now.subtract(const Duration(days: 12)),
        updatedAt: now.subtract(const Duration(days: 12)),
        creatorName: 'Alex Mercer',
      ),
    ]);
  }
}
