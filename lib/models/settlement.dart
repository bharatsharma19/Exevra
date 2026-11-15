import 'json_reader.dart';
import 'money.dart';

enum SettlementStatus { pending, confirmed, voided }

enum SettlementAction { recorded, confirmed, voided }

/// A payment between two group members. The payer records it as
/// [SettlementStatus.pending]; it counts towards balances only once the
/// payee confirms it. Either party or the admin can void it.
class Settlement {
  const Settlement({
    required this.id,
    required this.groupId,
    required this.fromUser,
    required this.toUser,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.note,
    this.createdBy,
    this.confirmedAt,
    this.voidedAt,
    this.voidedBy,
    this.voidReason,
  });

  static const String columns =
      'id,group_id,from_user,to_user,amount_minor,currency,status,note,'
      'created_by,created_at,confirmed_at,voided_at,voided_by,void_reason';

  final String id;
  final String groupId;

  /// Payer and payee. Null when that account was deleted.
  final String? fromUser;
  final String? toUser;

  final Money amount;
  final SettlementStatus status;
  final String? note;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final DateTime? voidedAt;
  final String? voidedBy;
  final String? voidReason;

  bool get isPending => status == SettlementStatus.pending;
  bool get isConfirmed => status == SettlementStatus.confirmed;
  bool get isVoided => status == SettlementStatus.voided;

  /// Only the payee confirms, and only while pending.
  bool canConfirm(String? userId) =>
      isPending && userId != null && userId == toUser;

  /// Payer, payee or group admin may void anything not already voided.
  bool canVoid(String? userId, {required bool isGroupAdmin}) =>
      !isVoided &&
      userId != null &&
      (isGroupAdmin || userId == fromUser || userId == toUser);

  factory Settlement.fromJson(Object? data) {
    final r = JsonReader.of(data, 'Settlement');
    return Settlement(
      id: r.nonEmpty('id'),
      groupId: r.nonEmpty('group_id'),
      fromUser: r.optString('from_user'),
      toUser: r.optString('to_user'),
      amount: r.money('amount_minor'),
      status: r.enumValue('status', SettlementStatus.values),
      note: r.optString('note'),
      createdBy: r.optString('created_by'),
      createdAt: r.instant('created_at'),
      confirmedAt: r.optInstant('confirmed_at'),
      voidedAt: r.optInstant('voided_at'),
      voidedBy: r.optString('voided_by'),
      voidReason: r.optString('void_reason'),
    );
  }

  Settlement copyWith({
    SettlementStatus? status,
    Object? confirmedAt = unset,
    Object? voidedAt = unset,
    Object? voidedBy = unset,
    Object? voidReason = unset,
  }) {
    return Settlement(
      id: id,
      groupId: groupId,
      fromUser: fromUser,
      toUser: toUser,
      amount: amount,
      status: status ?? this.status,
      note: note,
      createdBy: createdBy,
      createdAt: createdAt,
      confirmedAt: pick<DateTime?>(confirmedAt, this.confirmedAt),
      voidedAt: pick<DateTime?>(voidedAt, this.voidedAt),
      voidedBy: pick<String?>(voidedBy, this.voidedBy),
      voidReason: pick<String?>(voidReason, this.voidReason),
    );
  }
}

/// One entry of a settlement's append-only audit trail.
class SettlementEvent {
  const SettlementEvent({
    required this.id,
    required this.settlementId,
    required this.groupId,
    required this.action,
    required this.at,
    this.actor,
    this.details = const {},
  });

  static const String columns =
      'id,settlement_id,group_id,actor,action,at,details';

  final String id;
  final String settlementId;
  final String groupId;
  final String? actor;
  final SettlementAction action;
  final DateTime at;
  final Map<String, dynamic> details;

  factory SettlementEvent.fromJson(Object? data) {
    final r = JsonReader.of(data, 'SettlementEvent');
    return SettlementEvent(
      id: r.nonEmpty('id'),
      settlementId: r.nonEmpty('settlement_id'),
      groupId: r.nonEmpty('group_id'),
      actor: r.optString('actor'),
      action: r.enumValue('action', SettlementAction.values),
      at: r.instant('at'),
      details: r.optObject('details') ?? const {},
    );
  }
}
