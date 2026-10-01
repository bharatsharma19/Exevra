/// Model representing an expense item (Personal or Group)
class Expense {
  final String id;
  final String userId;
  final String? groupId;
  final String title;
  final double amount;
  final String category;
  final DateTime date;
  final String? notes;
  final String? receiptUrl;
  final bool isPersonal;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? creatorName;

  const Expense({
    required this.id,
    required this.userId,
    this.groupId,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    this.notes,
    this.receiptUrl,
    required this.isPersonal,
    required this.createdAt,
    required this.updatedAt,
    this.creatorName,
  });

  /// Editing Permission: Any user who created an expense (personal or group) can edit it. Non-creators cannot edit.
  bool canEdit(String currentUserId) {
    return userId == currentUserId;
  }

  /// Deleting Permission: Personal expenses can only be deleted by the creator.
  /// Group expenses can ONLY be deleted by the designated Group Admin.
  bool canDelete(String currentUserId, bool isGroupAdmin) {
    if (isPersonal) {
      return userId == currentUserId;
    }
    return isGroupAdmin;
  }

  factory Expense.fromJson(Map<String, dynamic> json) {
    final rawAmount = json['amount'];
    final double parsedAmount = rawAmount is num
        ? rawAmount.toDouble()
        : (double.tryParse(rawAmount?.toString() ?? '0') ?? 0.0);

    final groupId = json['group_id'] as String?;
    final isPersonalExplicit = json['is_personal'] as bool?;

    String? creator;
    if (json['profiles'] != null && json['profiles'] is Map) {
      creator = (json['profiles'] as Map<String, dynamic>)['display_name'] as String?;
    } else if (json['creator_name'] != null) {
      creator = json['creator_name'] as String?;
    }

    return Expense(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      groupId: groupId,
      title: json['title'] as String? ?? 'Untitled Expense',
      amount: parsedAmount,
      category: json['category'] as String? ?? 'Other',
      date: json['date'] != null
          ? DateTime.parse(json['date'] as String)
          : DateTime.now(),
      notes: json['notes'] as String?,
      receiptUrl: json['receipt_url'] as String?,
      isPersonal: isPersonalExplicit ?? (groupId == null),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      creatorName: creator,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'group_id': groupId,
      'title': title,
      'amount': amount,
      'category': category,
      'date': date.toIso8601String(),
      'notes': notes,
      'receipt_url': receiptUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Expense copyWith({
    String? id,
    String? userId,
    String? groupId,
    String? title,
    double? amount,
    String? category,
    DateTime? date,
    String? notes,
    String? receiptUrl,
    bool? isPersonal,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? creatorName,
  }) {
    return Expense(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      groupId: groupId ?? this.groupId,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      date: date ?? this.date,
      notes: notes ?? this.notes,
      receiptUrl: receiptUrl ?? this.receiptUrl,
      isPersonal: isPersonal ?? this.isPersonal,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      creatorName: creatorName ?? this.creatorName,
    );
  }
}
