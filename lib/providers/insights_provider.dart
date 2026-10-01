import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/insight_model.dart';
import '../services/supabase_service.dart';
import '../core/utils/haptics.dart';
import 'auth_provider.dart';
import 'expense_provider.dart';

class InsightState {
  final String timeframe; // 'weekly', 'monthly', 'yearly'
  final FinancialInsight insight;
  final bool isLoading;
  final String? errorMessage;

  const InsightState({
    this.timeframe = 'monthly',
    required this.insight,
    this.isLoading = false,
    this.errorMessage,
  });

  InsightState copyWith({
    String? timeframe,
    FinancialInsight? insight,
    bool? isLoading,
    String? errorMessage,
  }) {
    return InsightState(
      timeframe: timeframe ?? this.timeframe,
      insight: insight ?? this.insight,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class InsightNotifier extends StateNotifier<InsightState> {
  final SupabaseService _service;
  final Ref _ref;

  InsightNotifier(this._service, this._ref)
      : super(InsightState(insight: FinancialInsight.empty('monthly'))) {
    loadInsights();
  }

  Future<void> setTimeframe(String timeframe) async {
    if (state.timeframe == timeframe) return;
    AppHaptics.selection();
    state = state.copyWith(timeframe: timeframe);
    await loadInsights();
  }

  Future<void> loadInsights() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final auth = _ref.read(authNotifierProvider);
      final groupId = auth.profile?.groupId;

      final data = await _service.getExpenseInsights(
        timeframe: state.timeframe,
        groupId: groupId,
      );

      state = state.copyWith(
        insight: data,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }
}

final insightProvider = StateNotifierProvider<InsightNotifier, InsightState>((ref) {
  final service = ref.watch(supabaseServiceProvider);
  // Auto-refresh when expenses change
  ref.watch(expenseProvider.select((s) => s.expenses.length));
  return InsightNotifier(service, ref);
});
