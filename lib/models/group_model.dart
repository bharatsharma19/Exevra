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
