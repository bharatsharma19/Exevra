import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../../models/balance.dart';
import '../../models/json_reader.dart';
import '../../models/money.dart';
import '../../models/settlement.dart';
import '../supabase_client_provider.dart';

/// Settlements between members. Writes only through RPCs; the payer
/// records (pending), the payee confirms, either party or the admin voids.
abstract interface class SettlementRepository {
  /// Newest first.
  Future<List<Settlement>> list(String groupId, {int limit = 50});

  /// Audit trail of one settlement, oldest first.
  Future<List<SettlementEvent>> events(String settlementId);

  /// Records a pending payment from the caller to [toUser].
  Future<Settlement> record({
    required String groupId,
    required String toUser,
    required Money amount,
    String? note,
  });

  Future<Settlement> confirm(String settlementId);

  Future<Settlement> voidSettlement(String settlementId, {String? reason});
}

/// Server-computed balances and settle-up suggestions.
abstract interface class BalanceRepository {
  Future<List<GroupBalance>> balances(String groupId);
  Future<List<SettleSuggestion>> suggestions(String groupId);
}

final settlementRepositoryProvider = Provider<SettlementRepository>(
  (ref) => SupabaseSettlementRepository(ref.watch(supabaseClientProvider)),
);

final balanceRepositoryProvider = Provider<BalanceRepository>(
  (ref) => SupabaseBalanceRepository(ref.watch(supabaseClientProvider)),
);

class SupabaseSettlementRepository implements SettlementRepository {
  SupabaseSettlementRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Settlement>> list(String groupId, {int limit = 50}) {
    return ErrorMapper.guard(() async {
      final rows = await _client
          .from('settlements')
          .select(Settlement.columns)
          .eq('group_id', groupId)
          .order('created_at', ascending: false)
          .limit(limit);
      return parseList(rows, Settlement.fromJson, 'Settlement');
    });
  }

  @override
  Future<List<SettlementEvent>> events(String settlementId) {
    return ErrorMapper.guard(() async {
      final rows = await _client
          .from('settlement_events')
          .select(SettlementEvent.columns)
          .eq('settlement_id', settlementId)
          .order('at', ascending: true);
      return parseList(rows, SettlementEvent.fromJson, 'SettlementEvent');
    });
  }

  @override
  Future<Settlement> record({
    required String groupId,
    required String toUser,
    required Money amount,
    String? note,
  }) {
    return ErrorMapper.guard(() async {
      if (!amount.isPositive || amount.amountMinor > Money.maxAmountMinor) {
        throw const AppFailure.validation(
          field: 'amount',
          key: 'invalid_amount',
        );
      }
      final trimmed = note?.trim();
      if (trimmed != null && trimmed.length > 200) {
        throw const AppFailure.validation(field: 'note', key: 'invalid_note');
      }
      final data = await _client.rpc<Object?>(
        'record_settlement',
        params: {
          'p_group_id': groupId,
          'p_to_user': toUser,
          'p_amount_minor': amount.amountMinor,
          'p_note': trimmed == null || trimmed.isEmpty ? null : trimmed,
        },
      );
      return Settlement.fromJson(singleResult(data));
    });
  }

  @override
  Future<Settlement> confirm(String settlementId) {
    return ErrorMapper.guard(() async {
      final data = await _client.rpc<Object?>(
        'confirm_settlement',
        params: {'p_settlement_id': settlementId},
      );
      return Settlement.fromJson(singleResult(data));
    });
  }

  @override
  Future<Settlement> voidSettlement(String settlementId, {String? reason}) {
    return ErrorMapper.guard(() async {
      final trimmed = reason?.trim();
      if (trimmed != null && trimmed.length > 200) {
        throw const AppFailure.validation(
          field: 'reason',
          key: 'invalid_reason',
        );
      }
      final data = await _client.rpc<Object?>(
        'void_settlement',
        params: {
          'p_settlement_id': settlementId,
          'p_reason': trimmed == null || trimmed.isEmpty ? null : trimmed,
        },
      );
      return Settlement.fromJson(singleResult(data));
    });
  }
}

class SupabaseBalanceRepository implements BalanceRepository {
  SupabaseBalanceRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<GroupBalance>> balances(String groupId) {
    return ErrorMapper.guard(() async {
      final data = await _client.rpc<Object?>(
        'get_group_balances',
        params: {'p_group_id': groupId},
      );
      return parseList(data, GroupBalance.fromJson, 'GroupBalance');
    });
  }

  @override
  Future<List<SettleSuggestion>> suggestions(String groupId) {
    return ErrorMapper.guard(() async {
      final data = await _client.rpc<Object?>(
        'get_group_settle_suggestions',
        params: {'p_group_id': groupId},
      );
      return parseList(data, SettleSuggestion.fromJson, 'SettleSuggestion');
    });
  }
}
