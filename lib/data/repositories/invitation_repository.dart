import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../../core/utils/date_helpers.dart';
import '../../models/group.dart';
import '../../models/invitation.dart';
import '../../models/json_reader.dart';
import '../supabase_client_provider.dart';

/// Email invitations. Tokens are created on the server and only ever
/// travel in the invitee's link.
abstract interface class InvitationRepository {
  /// Creates an invitation and asks the server to email it. When the email
  /// could not be sent the result has `sent == false` and a share link.
  Future<SentInvitation> send({
    required String groupId,
    required String email,
    GroupRole role = GroupRole.member,
  });

  /// Details for the invitee (their confirmed email must match).
  Future<InvitationDetails> details(String token);

  /// Accepts the invitation; returns the joined group's id.
  Future<String> accept(String token);

  Future<void> decline(String token);

  /// Revokes a pending invitation (admin only).
  Future<void> revoke(String invitationId);

  /// Pending, unexpired invitations of a group (admin only).
  Future<List<GroupInvitation>> listPending(String groupId);
}

final invitationRepositoryProvider = Provider<InvitationRepository>(
  (ref) => SupabaseInvitationRepository(ref.watch(supabaseClientProvider)),
);

class SupabaseInvitationRepository implements InvitationRepository {
  SupabaseInvitationRepository(this._client);

  final SupabaseClient _client;

  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  @override
  Future<SentInvitation> send({
    required String groupId,
    required String email,
    GroupRole role = GroupRole.member,
  }) {
    return ErrorMapper.guard(() async {
      final normalized = email.trim().toLowerCase();
      if (!_email.hasMatch(normalized) || normalized.length > 254) {
        throw const AppFailure.validation(field: 'email', key: 'invalid_email');
      }
      if (role == GroupRole.admin) {
        throw const AppFailure.validation(key: 'invalid_role');
      }
      final response = await _client.functions.invoke(
        'send-invite',
        body: {'group_id': groupId, 'email': normalized, 'role': role.name},
      );
      return SentInvitation.fromJson(response.data);
    });
  }

  @override
  Future<InvitationDetails> details(String token) {
    return ErrorMapper.guard(() async {
      final data = await _client.rpc<Object?>(
        'get_invitation_details',
        params: {'p_token': token},
      );
      return InvitationDetails.fromJson(singleResult(data));
    });
  }

  @override
  Future<String> accept(String token) {
    return ErrorMapper.guard(() async {
      final data = await _client.rpc<Object?>(
        'accept_group_invitation',
        params: {'p_token': token},
      );
      return JsonReader.of(
        singleResult(data),
        'AcceptResult',
      ).nonEmpty('group_id');
    });
  }

  @override
  Future<void> decline(String token) {
    return ErrorMapper.guard(() async {
      await _client.rpc<Object?>(
        'decline_group_invitation',
        params: {'p_token': token},
      );
    });
  }

  @override
  Future<void> revoke(String invitationId) {
    return ErrorMapper.guard(() async {
      await _client.rpc<Object?>(
        'revoke_group_invitation',
        params: {'p_invitation_id': invitationId},
      );
    });
  }

  @override
  Future<List<GroupInvitation>> listPending(String groupId) {
    return ErrorMapper.guard(() async {
      final rows = await _client
          .from('group_invitations')
          .select(GroupInvitation.columns)
          .eq('group_id', groupId)
          .eq('status', 'pending')
          .gt('expires_at', DateHelpers.toUtcIso(DateTime.now()))
          .order('created_at', ascending: false);
      return parseList(rows, GroupInvitation.fromJson, 'GroupInvitation');
    });
  }
}
