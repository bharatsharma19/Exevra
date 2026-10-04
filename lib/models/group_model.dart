/// Model representing a collaborative expense group and its members
class ExpenseGroup {
  final String id;
  final String name;
  final String inviteCode;
  final String adminId;
  final DateTime createdAt;
  final int membersCount;

  const ExpenseGroup({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.adminId,
    required this.createdAt,
    this.membersCount = 1,
  });

  bool isAdmin(String userId) => adminId == userId;

  factory ExpenseGroup.fromJson(Map<String, dynamic> json) {
    return ExpenseGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      inviteCode: json['invite_code'] as String,
      adminId: json['admin_id'] as String,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      membersCount: json['members_count'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'invite_code': inviteCode,
      'admin_id': adminId,
      'created_at': createdAt.toIso8601String(),
      'members_count': membersCount,
    };
  }

  ExpenseGroup copyWith({
    String? id,
    String? name,
    String? inviteCode,
    String? adminId,
    DateTime? createdAt,
    int? membersCount,
  }) {
    return ExpenseGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      inviteCode: inviteCode ?? this.inviteCode,
      adminId: adminId ?? this.adminId,
      createdAt: createdAt ?? this.createdAt,
      membersCount: membersCount ?? this.membersCount,
    );
  }
}

class GroupMember {
  final String id;
  final String groupId;
  final String userId;
  final String role; // 'admin', 'member', or 'viewer'
  final String? displayName;
  final String? avatarUrl;
  final DateTime joinedAt;
  final String? invitedBy;

  const GroupMember({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.role,
    this.displayName,
    this.avatarUrl,
    required this.joinedAt,
    this.invitedBy,
  });

  bool get isAdmin => role == 'admin';
  bool get isApprovedMember => role == 'member';
  bool get isViewerOnly => role == 'viewer';
  bool get canAddExpenses => role == 'admin' || role == 'member';

  GroupMember copyWith({
    String? id,
    String? groupId,
    String? userId,
    String? role,
    String? displayName,
    String? avatarUrl,
    DateTime? joinedAt,
    String? invitedBy,
  }) {
    return GroupMember(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      joinedAt: joinedAt ?? this.joinedAt,
      invitedBy: invitedBy ?? this.invitedBy,
    );
  }

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      userId: json['user_id'] as String,
      role: json['role'] as String? ?? 'member',
      displayName: json['profiles'] != null
          ? (json['profiles'] as Map<String, dynamic>)['display_name'] as String?
          : json['display_name'] as String?,
      avatarUrl: json['profiles'] != null
          ? (json['profiles'] as Map<String, dynamic>)['avatar_url'] as String?
          : json['avatar_url'] as String?,
      joinedAt: json['joined_at'] != null
          ? DateTime.parse(json['joined_at'] as String)
          : DateTime.now(),
      invitedBy: json['invited_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'group_id': groupId,
      'user_id': userId,
      'role': role,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'joined_at': joinedAt.toIso8601String(),
      'invited_by': invitedBy,
    };
  }
}

class SettlementDebt {
  final String fromUserId;
  final String fromUserName;
  final String toUserId;
  final String toUserName;
  final double amount;

  const SettlementDebt({
    required this.fromUserId,
    required this.fromUserName,
    required this.toUserId,
    required this.toUserName,
    required this.amount,
  });
}

class GroupInvitation {
  final String id;
  final String groupId;
  final String? groupName;
  final String inviterId;
  final String? inviterName;
  final String email;
  final String role;
  final String token;
  final String status; // 'pending', 'accepted', 'declined', 'expired', 'revoked'
  final DateTime expiresAt;
  final DateTime createdAt;
  final DateTime? acceptedAt;

  const GroupInvitation({
    required this.id,
    required this.groupId,
    this.groupName,
    required this.inviterId,
    this.inviterName,
    required this.email,
    required this.role,
    required this.token,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
    this.acceptedAt,
  });

  bool get isExpired =>
      status == 'expired' || DateTime.now().isAfter(expiresAt);
  bool get isPending => status == 'pending' && !isExpired;
  bool get isAccepted => status == 'accepted';

  factory GroupInvitation.fromJson(Map<String, dynamic> json) {
    return GroupInvitation(
      id: json['id'] as String? ?? json['invitation_id'] as String? ?? '',
      groupId: json['group_id'] as String? ?? '',
      groupName: json['group_name'] as String?,
      inviterId: json['inviter_id'] as String? ?? '',
      inviterName: json['inviter_name'] as String?,
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? 'member',
      token: json['token'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : DateTime.now().add(const Duration(days: 7)),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      acceptedAt: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'group_id': groupId,
      'group_name': groupName,
      'inviter_id': inviterId,
      'inviter_name': inviterName,
      'email': email,
      'role': role,
      'token': token,
      'status': status,
      'expires_at': expiresAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'accepted_at': acceptedAt?.toIso8601String(),
    };
  }
}

class Settlement {
  final String id;
  final String groupId;
  final String payerId;
  final String? payerName;
  final String payeeId;
  final String? payeeName;
  final double amount;
  final DateTime date;
  final String? notes;
  final DateTime createdAt;

  const Settlement({
    required this.id,
    required this.groupId,
    required this.payerId,
    this.payerName,
    required this.payeeId,
    this.payeeName,
    required this.amount,
    required this.date,
    this.notes,
    required this.createdAt,
  });

  factory Settlement.fromJson(Map<String, dynamic> json) {
    final rawAmount = json['amount'];
    final double parsedAmount = rawAmount is num
        ? rawAmount.toDouble()
        : (double.tryParse(rawAmount?.toString() ?? '0') ?? 0.0);

    return Settlement(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      payerId: json['payer_id'] as String,
      payerName: json['payer_name'] as String?,
      payeeId: json['payee_id'] as String,
      payeeName: json['payee_name'] as String?,
      amount: parsedAmount,
      date: json['date'] != null
          ? DateTime.parse(json['date'] as String)
          : DateTime.now(),
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'group_id': groupId,
      'payer_id': payerId,
      'payer_name': payerName,
      'payee_id': payeeId,
      'payee_name': payeeName,
      'amount': amount,
      'date': date.toIso8601String(),
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

