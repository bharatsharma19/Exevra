import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../../models/insights.dart';
import '../supabase_client_provider.dart';

/// Server-side spending aggregates, bucketed in the user's time zone.
abstract interface class InsightsRepository {
  Future<ExpenseInsights> fetch({
    required InsightScope scope,
    required InsightTimeframe timeframe,
    required String timeZone,
    required String preferredCurrency,
    String? groupId,
  });
}

final insightsRepositoryProvider = Provider<InsightsRepository>(
  (ref) => SupabaseInsightsRepository(ref.watch(supabaseClientProvider)),
);

class SupabaseInsightsRepository implements InsightsRepository {
  SupabaseInsightsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<ExpenseInsights> fetch({
    required InsightScope scope,
    required InsightTimeframe timeframe,
    required String timeZone,
    required String preferredCurrency,
    String? groupId,
  }) {
    return ErrorMapper.guard(() async {
      if (scope == InsightScope.group && groupId == null) {
        throw const AppFailure.validation(key: 'invalid_target');
      }
      final data = await _client.rpc<Object?>(
        'get_expense_insights',
        params: {
          'p_scope': scope.name,
          'p_group_id': scope == InsightScope.group ? groupId : null,
          'p_timeframe': timeframe.name,
          'p_tz': timeZone,
        },
      );
      return ExpenseInsights.fromJson(
        singleResult(data),
        scope: scope,
        timeframe: timeframe,
        preferredCurrency: preferredCurrency,
      );
    });
  }
}
