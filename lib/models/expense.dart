import '../core/constants/app_constants.dart';
import '../core/utils/date_helpers.dart';
import 'json_reader.dart';
import 'money.dart';

/// An expense, personal (`groupId == null`) or in a group.
///
/// Personal vs group is derived from [groupId] only; there is no separate
/// flag that could disagree with it.
class Expense {
  const Expense({
    required this.id,
    required this.userId,
    required this.groupId,
    required this.title,
    required this.amount,
    required this.category,
    required this.spentAt,
    required this.createdAt,
    required this.updatedAt,
    this.note,
    this.receiptUrl,
    this.isSyncing = false,
  });

  /// Columns read from `public.expenses`.
  static const String columns =
      'id,user_id,group_id,title,amount_minor,currency,category,spent_at,'
      'note,receipt_url,created_at,updated_at';

  /// Prefix of client-side ids for optimistic rows that are not saved yet.
  static const String localIdPrefix = 'local-';

  final String id;

  /// The payer. Null when the payer deleted their account ("Former member").
  final String? userId;

  /// Null for a personal expense.
  final String? groupId;

  final String title;
  final Money amount;
  final String category;

  /// When the money was spent (UTC instant; shown in local time).
  final DateTime spentAt;

  final String? note;
  final String? receiptUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// True while an optimistic change has not been confirmed by the server.
  final bool isSyncing;

  bool get isPersonal => groupId == null;
  bool get isGroup => groupId != null;
  bool get isFormerMemberPayer => userId == null;

  /// Mirrors the server rules: the owner edits a personal expense; the
  /// payer edits a group expense while they can add expenses.
  bool canEdit(String? currentUserId, {bool canAddToGroup = false}) {
    if (currentUserId == null || userId != currentUserId) return false;
    return isPersonal || canAddToGroup;
  }

  /// Mirrors the server rules: the owner deletes a personal expense; a
  /// group expense can be deleted by its payer (while admin or member) or
  /// by the group admin.
  bool canDelete(
    String? currentUserId, {
    bool isGroupAdmin = false,
    bool canAddToGroup = false,
  }) {
    if (currentUserId == null) return false;
    if (isPersonal) return userId == currentUserId;
    return isGroupAdmin || (userId == currentUserId && canAddToGroup);
  }

  factory Expense.fromJson(Object? data) {
    final r = JsonReader.of(data, 'Expense');
    return Expense(
      id: r.nonEmpty('id'),
      userId: r.optString('user_id'),
      groupId: r.optString('group_id'),
      title: r.string('title'),
      amount: r.money('amount_minor'),
      category: r.string('category'),
      spentAt: r.instant('spent_at'),
      note: r.optString('note'),
      receiptUrl: r.optString('receipt_url'),
      createdAt: r.instant('created_at'),
      updatedAt: r.instant('updated_at'),
    );
  }

  /// Fields the client may change on an existing expense. `note` is always
  /// sent so it can be cleared; `group_id` and `user_id` never change.
  Map<String, Object?> toUpdateJson() => {
    'title': title.trim(),
    'amount_minor': amount.amountMinor,
    'currency': amount.currency,
    'category': category,
    'spent_at': DateHelpers.toUtcIso(spentAt),
    'note': _cleanNote(note),
  };

  Expense copyWith({
    String? id,
    Object? userId = unset,
    Object? groupId = unset,
    String? title,
    Money? amount,
    String? category,
    DateTime? spentAt,
    Object? note = unset,
    Object? receiptUrl = unset,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSyncing,
  }) {
    return Expense(
      id: id ?? this.id,
      userId: pick<String?>(userId, this.userId),
      groupId: pick<String?>(groupId, this.groupId),
      title: title ?? this.title,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      spentAt: spentAt ?? this.spentAt,
      note: pick<String?>(note, this.note),
      receiptUrl: pick<String?>(receiptUrl, this.receiptUrl),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSyncing: isSyncing ?? this.isSyncing,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Expense &&
      other.id == id &&
      other.userId == userId &&
      other.groupId == groupId &&
      other.title == title &&
      other.amount == amount &&
      other.category == category &&
      other.spentAt == spentAt &&
      other.note == note &&
      other.receiptUrl == receiptUrl &&
      other.isSyncing == isSyncing;

  @override
  int get hashCode =>
      Object.hash(id, userId, groupId, title, amount, category, spentAt, note);
}

/// A new expense before the server assigns its id and timestamps.
class ExpenseDraft {
  const ExpenseDraft({
    required this.title,
    required this.amount,
    required this.category,
    required this.spentAt,
    this.groupId,
    this.note,
  });

  /// The fields of [expense] as a new expense (to re-create a deleted one
  /// or to copy it into another scope). The server assigns a new id.
  factory ExpenseDraft.fromExpense(Expense expense, {Object? groupId = unset}) {
    return ExpenseDraft(
      title: expense.title,
      amount: expense.amount,
      category: expense.category,
      spentAt: expense.spentAt,
      groupId: pick<String?>(groupId, expense.groupId),
      note: expense.note,
    );
  }

  final String title;
  final Money amount;
  final String category;
  final DateTime spentAt;
  final String? groupId;
  final String? note;

  bool get isPersonal => groupId == null;

  /// Insert payload. The server sets `id`, `created_at` and `updated_at`;
  /// `user_id` is the caller.
  Map<String, Object?> toInsertJson(String userId) => {
    'user_id': userId,
    'group_id': groupId,
    'title': title.trim(),
    'amount_minor': amount.amountMinor,
    'currency': amount.currency,
    'category': category,
    'spent_at': DateHelpers.toUtcIso(spentAt),
    'note': _cleanNote(note),
  };

  /// Local placeholder shown until the server answers.
  Expense toOptimistic({required String localId, required String userId}) {
    final now = DateTime.now().toUtc();
    return Expense(
      id: localId,
      userId: userId,
      groupId: groupId,
      title: title.trim(),
      amount: amount,
      category: category,
      spentAt: spentAt.toUtc(),
      note: _cleanNote(note),
      createdAt: now,
      updatedAt: now,
      isSyncing: true,
    );
  }

  /// Client-side checks matching the database constraints.
  /// Returns a validation message key, or null when valid.
  String? validate() {
    final t = title.trim();
    if (t.isEmpty || t.length > 120) return 'invalid_title';
    final n = _cleanNote(note);
    if (n != null && n.length > 500) return 'invalid_note';
    if (!AppConstants.categories.any((c) => c.name == category)) {
      return 'invalid_category';
    }
    if (!amount.isPositive || amount.amountMinor > Money.maxAmountMinor) {
      return 'invalid_amount';
    }
    return null;
  }
}

String? _cleanNote(String? note) {
  final trimmed = note?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
