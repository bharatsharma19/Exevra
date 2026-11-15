import 'json_reader.dart';
import 'money.dart';

/// One participant's balance in a group (from `get_group_balances`), in
/// the group currency.
///
/// `net = paid - owed + settledOut - settledIn`. Positive: the others owe
/// them. Negative: they owe the others. Only confirmed settlements count.
class GroupBalance {
  const GroupBalance({
    required this.userId,
    required this.displayName,
    required this.paid,
    required this.owed,
    required this.settledOut,
    required this.settledIn,
    required this.net,
  });

  /// Null for the aggregated "Former member" row.
  final String? userId;
  final String displayName;
  final Money paid;
  final Money owed;
  final Money settledOut;
  final Money settledIn;
  final Money net;

  bool get isFormerMember => userId == null;
  bool get isSettled => net.isZero;

  factory GroupBalance.fromJson(Object? data) {
    final r = JsonReader.of(data, 'GroupBalance');
    final userId = r.optString('user_id');
    final name = r.optString('display_name')?.trim();
    return GroupBalance(
      userId: userId,
      displayName: name == null || name.isEmpty
          ? (userId == null ? 'Former member' : 'Member')
          : name,
      paid: r.money('paid_minor'),
      owed: r.money('owed_minor'),
      settledOut: r.money('settled_out_minor'),
      settledIn: r.money('settled_in_minor'),
      net: r.money('net_minor'),
    );
  }
}

/// A suggested transfer that settles debts (`get_group_settle_suggestions`).
class SettleSuggestion {
  const SettleSuggestion({
    required this.fromUser,
    required this.toUser,
    required this.amount,
  });

  final String fromUser;
  final String toUser;
  final Money amount;

  factory SettleSuggestion.fromJson(Object? data) {
    final r = JsonReader.of(data, 'SettleSuggestion');
    return SettleSuggestion(
      fromUser: r.nonEmpty('from_user'),
      toUser: r.nonEmpty('to_user'),
      amount: r.money('amount_minor'),
    );
  }
}
