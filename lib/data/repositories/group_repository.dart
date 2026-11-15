import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../../models/group.dart';
import '../../models/json_reader.dart';
import '../supabase_client_provider.dart';

/// Outcome of `leave_group`.
class LeaveResult {
  const LeaveResult({required this.groupDeleted, this.newAdminId});

  final bool groupDeleted;
  final String? newAdminId;
}

/// A freshly issued invite code (admin only).
class InviteCode {
  const InviteCode(this.code, this.expiresAt);

  final String code;
  final DateTime expiresAt;

  /// The code grouped for display: `XXXX-XXXX-XXXX-XXXX`.
  String get display => Group.formatInviteCode(code);
}

/// Groups and membership. Every write goes through a server RPC that
/// raises when the caller is not allowed or nothing changed.
abstract interface class GroupRepository {
  /// Groups the user belongs to, newest first, pending requests included.
  Future<List<Group>> fetchMyGroups();

  /// Creates a group with the caller as admin; returns its id.
  Future<String> createGroup({required String name, required String currency});

  Future<LeaveResult> leaveGroup(String groupId);

  /// Deletes the group and all its data (admin only).
  Future<void> deleteGroup(String groupId);

  Future<void> transferAdmin(String groupId, String newAdminId);
  Future<void> removeMember(String groupId, String userId);
  Future<void> approveMember(
    String groupId,
    String userId, {
    GroupRole role = GroupRole.member,
  });
  Future<void> setMemberRole(String groupId, String userId, GroupRole role);

  /// Sets the active group on the profile; null means personal mode.
  Future<void> setActiveGroup(String? groupId);

  /// Requests to join by invite code. Success means a pending request
  /// that the admin must approve.
  Future<JoinRequest> joinByCode(String code);

  Future<InviteCode> rotateInviteCode(String groupId);

  /// Members as other members see them (no email or phone).
  Future<List<GroupMember>> fetchMembers(String groupId);
}

final groupRepositoryProvider = Provider<GroupRepository>(
  (ref) => SupabaseGroupRepository(ref.watch(supabaseClientProvider)),
);

class SupabaseGroupRepository implements GroupRepository {
  SupabaseGroupRepository(this._client);

  final SupabaseClient _client;

  Future<Object?> _rpc(String fn, [Map<String, Object?>? params]) =>
      _client.rpc<Object?>(fn, params: params);

  @override
  Future<List<Group>> fetchMyGroups() {
    return ErrorMapper.guard(() async {
      final data = await _rpc('get_user_groups');
      return parseList(data ?? const <Object?>[], Group.fromJson, 'Group');
    });
  }

  @override
  Future<String> createGroup({required String name, required String currency}) {
    return ErrorMapper.guard(() async {
      final trimmed = name.trim();
      if (trimmed.isEmpty || trimmed.length > 60) {
        throw const AppFailure.validation(
          field: 'name',
          key: 'invalid_group_name',
        );
      }
      final data = await _rpc('create_group', {
        'p_name': trimmed,
        'p_currency': currency,
      });
      return JsonReader.of(singleResult(data), 'Group').nonEmpty('id');
    });
  }

  @override
  Future<LeaveResult> leaveGroup(String groupId) {
    return ErrorMapper.guard(() async {
      final data = await _rpc('leave_group', {'p_group_id': groupId});
      final r = JsonReader.of(singleResult(data), 'LeaveResult');
      return LeaveResult(
        groupDeleted: r.boolean('group_deleted', fallback: false),
        newAdminId: r.optString('new_admin_id'),
      );
    });
  }

  @override
  Future<void> deleteGroup(String groupId) {
    return ErrorMapper.guard(() async {
      final rows = await _client
          .from('groups')
          .delete()
          .eq('id', groupId)
          .select('id');
      requireRows(rows);
    });
  }

  @override
  Future<void> transferAdmin(String groupId, String newAdminId) {
    return ErrorMapper.guard(() async {
      await _rpc('transfer_admin', {
        'p_group_id': groupId,
        'p_new_admin': newAdminId,
      });
    });
  }

  @override
  Future<void> removeMember(String groupId, String userId) {
    return ErrorMapper.guard(() async {
      await _rpc('remove_member', {'p_group_id': groupId, 'p_user_id': userId});
    });
  }

  @override
  Future<void> approveMember(
    String groupId,
    String userId, {
    GroupRole role = GroupRole.member,
  }) {
    return ErrorMapper.guard(() async {
      if (role == GroupRole.admin) {
        throw const AppFailure.validation(key: 'invalid_role');
      }
      await _rpc('approve_member', {
        'p_group_id': groupId,
        'p_user_id': userId,
        'p_role': role.name,
      });
    });
  }

  @override
  Future<void> setMemberRole(String groupId, String userId, GroupRole role) {
    return ErrorMapper.guard(() async {
      if (role == GroupRole.admin) {
        throw const AppFailure.validation(key: 'invalid_role');
      }
      await _rpc('set_member_role', {
        'p_group_id': groupId,
        'p_user_id': userId,
        'p_role': role.name,
      });
    });
  }

  @override
  Future<void> setActiveGroup(String? groupId) {
    return ErrorMapper.guard(() async {
      await _rpc('set_active_group', {'p_group_id': groupId});
    });
  }

  @override
  Future<JoinRequest> joinByCode(String code) {
    return ErrorMapper.guard(() async {
      final normalized = code.trim();
      if (normalized.isEmpty) {
        throw const AppFailure.validation(field: 'code', key: 'invalid_code');
      }
      final data = await _rpc('join_group_by_code', {'p_code': normalized});
      final r = JsonReader.of(singleResult(data), 'JoinResult');
      if (!r.boolean('success')) {
        final error = r.optString('error') ?? 'invalid_code';
        throw switch (error) {
          'rate_limited' => AppFailure.rateLimited(
            retryAfter: r.optInstant('retry_after'),
          ),
          'already_member' => const AppFailure.conflict(key: 'already_member'),
          _ => AppFailure.business(error),
        };
      }
      return JoinRequest(
        groupId: r.nonEmpty('group_id'),
        groupName: r.string('group_name'),
        status: r.enumValue(
          'status',
          MemberStatus.values,
          fallback: MemberStatus.pending,
        ),
      );
    });
  }

  @override
  Future<InviteCode> rotateInviteCode(String groupId) {
    return ErrorMapper.guard(() async {
      final data = await _rpc('rotate_invite_code', {'p_group_id': groupId});
      final r = JsonReader.of(singleResult(data), 'InviteCode');
      return InviteCode(
        r.nonEmpty('invite_code'),
        r.instant('invite_code_expires_at'),
      );
    });
  }

  @override
  Future<List<GroupMember>> fetchMembers(String groupId) {
    return ErrorMapper.guard(() async {
      final data = await _rpc('get_group_members', {'p_group_id': groupId});
      return parseList(data, GroupMember.fromJson, 'GroupMember');
    });
  }
}
