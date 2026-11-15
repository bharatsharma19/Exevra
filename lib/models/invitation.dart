import 'group.dart';
import 'json_reader.dart';

enum InvitationStatus { pending, accepted, declined, revoked, expired }

/// An email invitation as the group admin sees it (pending list).
/// Tokens are never readable; only the invitee's link carries one.
class GroupInvitation {
  const GroupInvitation({
    required this.id,
    required this.groupId,
    required this.inviterId,
    required this.email,
    required this.role,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
    this.respondedAt,
  });

  static const String columns =
      'id,group_id,inviter_id,email,role,status,expires_at,created_at,'
      'responded_at';

  final String id;
  final String groupId;
  final String inviterId;
  final String email;
  final GroupRole role;
  final InvitationStatus status;
  final DateTime expiresAt;
  final DateTime createdAt;
  final DateTime? respondedAt;

  bool isExpiredAt(DateTime now) =>
      status == InvitationStatus.expired || !now.isBefore(expiresAt);

  bool isPendingAt(DateTime now) =>
      status == InvitationStatus.pending && !isExpiredAt(now);

  factory GroupInvitation.fromJson(Object? data) {
    final r = JsonReader.of(data, 'GroupInvitation');
    return GroupInvitation(
      id: r.nonEmpty('id'),
      groupId: r.nonEmpty('group_id'),
      inviterId: r.nonEmpty('inviter_id'),
      email: r.string('email'),
      role: r.enumValue('role', GroupRole.values),
      status: r.enumValue('status', InvitationStatus.values),
      expiresAt: r.instant('expires_at'),
      createdAt: r.instant('created_at'),
      respondedAt: r.optInstant('responded_at'),
    );
  }
}

/// What the invitee sees before accepting (`get_invitation_details`).
class InvitationDetails {
  const InvitationDetails({
    required this.invitationId,
    required this.groupId,
    required this.groupName,
    required this.role,
    required this.status,
    required this.expiresAt,
    this.inviterName,
  });

  final String invitationId;
  final String groupId;
  final String groupName;
  final String? inviterName;
  final GroupRole role;
  final InvitationStatus status;
  final DateTime expiresAt;

  bool isActionableAt(DateTime now) =>
      status == InvitationStatus.pending && now.isBefore(expiresAt);

  factory InvitationDetails.fromJson(Object? data) {
    final r = JsonReader.of(data, 'InvitationDetails');
    return InvitationDetails(
      invitationId: r.nonEmpty('invitation_id'),
      groupId: r.nonEmpty('group_id'),
      groupName: r.string('group_name'),
      inviterName: r.optString('inviter_name'),
      role: r.enumValue('role', GroupRole.values),
      status: r.enumValue('status', InvitationStatus.values),
      expiresAt: r.instant('expires_at'),
    );
  }
}

/// Result of the `send-invite` Edge Function. The invitation exists even
/// when [sent] is false; then [shareUrl] can be shared by hand.
class SentInvitation {
  const SentInvitation({
    required this.invitationId,
    required this.sent,
    this.expiresAt,
    this.reason,
    this.shareUrl,
  });

  final String invitationId;
  final bool sent;
  final DateTime? expiresAt;

  /// `email_not_configured` or `email_failed` when [sent] is false.
  final String? reason;
  final String? shareUrl;

  factory SentInvitation.fromJson(Object? data) {
    final r = JsonReader.of(data, 'SentInvitation');
    final sent = r.boolean('sent');
    final shareUrl = r.optString('share_url');
    if (!sent && (shareUrl == null || !shareUrl.startsWith('https://'))) {
      throw const FormatException('SentInvitation.share_url: expected https');
    }
    return SentInvitation(
      invitationId: r.nonEmpty('invitation_id'),
      sent: sent,
      expiresAt: r.optInstant('expires_at'),
      reason: r.optString('reason'),
      shareUrl: shareUrl,
    );
  }
}
