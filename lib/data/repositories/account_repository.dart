import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../../models/json_reader.dart';
import '../supabase_client_provider.dart';

/// Account lifecycle operations that need the server's privileges.
abstract interface class AccountRepository {
  /// Deletes the account through the `delete-account` Edge Function.
  /// Completes only when the server confirms the deletion; otherwise
  /// throws an [AppFailure] and the account (and session) stay as they
  /// were.
  Future<void> deleteAccount({String? appleAuthorizationCode});
}

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => SupabaseAccountRepository(ref.watch(supabaseClientProvider)),
);

class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> deleteAccount({String? appleAuthorizationCode}) {
    return ErrorMapper.guard(() async {
      final response = await _client.functions.invoke(
        'delete-account',
        body: {'apple_authorization_code': ?appleAuthorizationCode},
      );
      final r = JsonReader.of(response.data, 'DeleteAccountResult');
      if (!r.boolean('deleted', fallback: false)) {
        throw const AppFailure.business('deletion_failed');
      }
    });
  }
}
