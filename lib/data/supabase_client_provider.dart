import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors/app_failure.dart';

/// The Supabase client. Repositories read it from here so tests can
/// replace whole repositories without touching Supabase.
final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// Rows returned by a write that must affect at least one row. An empty
/// result means RLS hid the row or it does not exist; that is a failure,
/// never a silent success.
List<Object?> requireRows(Object? data) {
  if (data is List && data.isNotEmpty) return data;
  throw const AppFailure.permissionDenied();
}

/// The single object an RPC returned (a composite row or a JSON object).
Object? singleResult(Object? data) {
  if (data is List) {
    if (data.length == 1) return data.first;
    throw const FormatException('Expected exactly one row');
  }
  return data;
}
