import 'json_reader.dart';

/// Role in a group. Pending members are always [viewer].
enum GroupRole { admin, member, viewer }

/// Membership state. A code join stays [pending] until an admin approves.
enum MemberStatus { pending, approved }

/// A group the signed-in user belongs to (from `get_user_groups`).
class Group {
  const Group({
    required this.id,
    required this.name,
    required this.currency,
    required this.adminId,
    required this.createdAt,
    required this.role,
    required this.status,
    this.joinedAt,
    this.membersCount = 1,
    this.inviteCode,
    this.inviteCodeExpiresAt,
  });

  final String id;
  final String name;

  /// Fixed group currency; every group expense and settlement uses it.
  final String currency;

  final String adminId;
  final DateTime createdAt;

  /// The signed-in user's role and status in this group.
  final GroupRole role;
  final MemberStatus status;
  final DateTime? joinedAt;

  /// Approved members.
  final int membersCount;

  /// Only present for the admin.
  final String? inviteCode;
  final DateTime? inviteCodeExpiresAt;

  bool get isPending => status == MemberStatus.pending;
  bool get isApproved => status == MemberStatus.approved;
  bool get isAdmin => isApproved && role == GroupRole.admin;
  bool get isViewer => role == GroupRole.viewer;

  /// Whether the user may add group expenses (approved admin or member).
  bool get canAddExpenses =>
      isApproved && (role == GroupRole.admin || role == GroupRole.member);

  /// Whether the user can read the group's data (approved, any role).
  bool get canRead => isApproved;

  /// The invite code grouped for display: `XXXX-XXXX-XXXX-XXXX`.
  String? get displayInviteCode {
    final code = inviteCode;
    return code == null ? null : formatInviteCode(code);
  }

  /// `XXXX-XXXX-XXXX-XXXX` grouping of a raw invite code.
  static String formatInviteCode(String code) {
    final parts = <String>[];
    for (var i = 0; i < code.length; i += 4) {
      parts.add(code.substring(i, i + 4 > code.length ? code.length : i + 4));
    }
    return parts.join('-');
  }

  factory Group.fromJson(Object? data) {
    final r = JsonReader.of(data, 'Group');
    return Group(
      id: r.nonEmpty('id'),
      name: r.string('name'),
      currency: r.string('currency').trim().toUpperCase(),
      adminId: r.nonEmpty('admin_id'),
      createdAt: r.instant('created_at'),
      role: r.enumValue('role', GroupRole.values),
      status: r.enumValue('status', MemberStatus.values),
      joinedAt: r.optInstant('joined_at'),
      membersCount: r.optInteger('members_count') ?? 1,
      inviteCode: r.optString('invite_code'),
      inviteCodeExpiresAt: r.optInstant('invite_code_expires_at'),
    );
  }

  Group copyWith({
    String? name,
    String? adminId,
    GroupRole? role,
    MemberStatus? status,
    int? membersCount,
    Object? inviteCode = unset,
    Object? inviteCodeExpiresAt = unset,
  }) {
    return Group(
      id: id,
      name: name ?? this.name,
      currency: currency,
      adminId: adminId ?? this.adminId,
      createdAt: createdAt,
      role: role ?? this.role,
      status: status ?? this.status,
      joinedAt: joinedAt,
      membersCount: membersCount ?? this.membersCount,
      inviteCode: pick<String?>(inviteCode, this.inviteCode),
      inviteCodeExpiresAt: pick<DateTime?>(
        inviteCodeExpiresAt,
        this.inviteCodeExpiresAt,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Group &&
      other.id == id &&
      other.name == name &&
      other.adminId == adminId &&
      other.role == role &&
      other.status == status &&
      other.membersCount == membersCount &&
      other.inviteCode == inviteCode;

  @override
  int get hashCode => Object.hash(id, name, adminId, role, status);
}

/// A member of a group as other members see them (from
/// `get_group_members`). Never carries another user's email or phone.
class GroupMember {
  const GroupMember({
    required this.userId,
    required this.role,
    required this.status,
    this.displayName,
    this.avatarUrl,
    this.joinedAt,
  });

  final String userId;
  final String? displayName;
  final String? avatarUrl;
  final GroupRole role;
  final MemberStatus status;
  final DateTime? joinedAt;

  bool get isAdmin => role == GroupRole.admin;
  bool get isPending => status == MemberStatus.pending;
  bool get isViewer => role == GroupRole.viewer;
  bool get canAddExpenses =>
      status == MemberStatus.approved &&
      (role == GroupRole.admin || role == GroupRole.member);

  /// Name to show, never blank.
  String get label {
    final name = displayName?.trim();
    return name == null || name.isEmpty ? 'Member' : name;
  }

  factory GroupMember.fromJson(Object? data) {
    final r = JsonReader.of(data, 'GroupMember');
    return GroupMember(
      userId: r.nonEmpty('user_id'),
      displayName: r.optString('display_name'),
      avatarUrl: r.optString('avatar_url'),
      role: r.enumValue('role', GroupRole.values),
      status: r.enumValue('status', MemberStatus.values),
      joinedAt: r.optInstant('joined_at'),
    );
  }

  GroupMember copyWith({GroupRole? role, MemberStatus? status}) {
    return GroupMember(
      userId: userId,
      displayName: displayName,
      avatarUrl: avatarUrl,
      role: role ?? this.role,
      status: status ?? this.status,
      joinedAt: joinedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GroupMember &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.role == role &&
      other.status == status;

  @override
  int get hashCode => Object.hash(userId, displayName, role, status);
}

/// Result of a successful `join_group_by_code`: a pending request.
class JoinRequest {
  const JoinRequest({
    required this.groupId,
    required this.groupName,
    required this.status,
  });

  final String groupId;
  final String groupName;
  final MemberStatus status;
}
