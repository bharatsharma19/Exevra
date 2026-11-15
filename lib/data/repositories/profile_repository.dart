import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../../models/profile.dart';
import '../supabase_client_provider.dart';

/// The signed-in user's own profile. Writes are partial column updates;
/// the whole row is never upserted, so nothing the client did not mean to
/// change is overwritten.
abstract interface class ProfileRepository {
  /// Throws [AppFailure] (not found when the row does not exist yet).
  Future<UserProfile> fetch(String userId);

  /// Writes only the fields set in [update] and returns the saved row.
  Future<UserProfile> update(String userId, ProfileUpdate update);
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => SupabaseProfileRepository(ref.watch(supabaseClientProvider)),
);

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<UserProfile> fetch(String userId) {
    return ErrorMapper.guard(() async {
      final row = await _client
          .from('profiles')
          .select(UserProfile.columns)
          .eq('id', userId)
          .maybeSingle();
      if (row == null) {
        throw const AppFailure.notFound(key: 'profile_not_found');
      }
      return UserProfile.fromJson(row);
    });
  }

  @override
  Future<UserProfile> update(String userId, ProfileUpdate update) {
    return ErrorMapper.guard(() async {
      final invalid = update.validate();
      if (invalid != null) throw AppFailure.validation(key: invalid);
      if (update.isEmpty) return fetch(userId);
      final rows = await _client
          .from('profiles')
          .update(update.fields)
          .eq('id', userId)
          .select(UserProfile.columns);
      return UserProfile.fromJson(requireRows(rows).first);
    });
  }
}
