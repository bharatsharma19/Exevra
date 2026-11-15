import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../models/user_profile.dart';
import '../constants/app_constants.dart';

/// Offline demo mode for local UI work without a backend.
///
/// It is enabled only with `--dart-define=DEMO=true` in a debug or profile
/// build. Release builds compile every demo path out because this constant
/// is false there, so an invalid configuration can never fall back to a
/// demo or fake session in production.
const bool kDemoMode = !kReleaseMode && bool.fromEnvironment('DEMO');

/// User id of the offline demo account.
const String kDemoUserId = 'demo-user-id';

/// Whether this run talks to the offline demo backend.
///
/// A demo build with a valid configuration talks to the real project, so
/// every demo fallback (fake sessions, local invitations, seeded data) is
/// gated on this flag rather than on [kDemoMode] alone. Always false outside
/// demo builds.
abstract final class DemoBackend {
  static bool _active = false;

  static bool get active => kDemoMode && _active;

  /// Called once from `main()` when the offline demo backend is chosen.
  static void activate() {
    if (!kDemoMode) {
      throw StateError('The demo backend is only available in demo mode.');
    }
    _active = true;
  }
}

/// True only for the offline demo account while the demo backend is in use.
/// Permission shortcuts for the demo account depend on this, so they never
/// apply in release builds or against a real backend.
bool isDemoUser(String? userId) => DemoBackend.active && userId == kDemoUserId;

/// Returns [userId], or the demo account's id when no one is signed in and
/// the demo backend is in use. Otherwise there is no fallback identity, so
/// this throws a [StateError].
String requireUserId(String? userId) {
  if (userId != null) return userId;
  if (DemoBackend.active) return kDemoUserId;
  throw StateError('Not signed in.');
}

/// Returns [userId] for UI permission checks. When no one is signed in it is
/// the demo account's id while the demo backend is in use, and otherwise an
/// empty id that matches no user, so checks fail closed.
String userIdForChecks(String? userId) =>
    userId ?? (DemoBackend.active ? kDemoUserId : '');

/// Placeholder backend used when demo mode runs without a configuration.
/// Requests to it fail fast, which routes the data layer to its in-memory
/// store.
const String kDemoSupabaseUrl = 'http://127.0.0.1:54321';
const String kDemoSupabaseAnonKey = 'sb_publishable_offline_demo_only';

/// A signed-in demo user and profile for offline UI work.
class DemoSession {
  DemoSession._(this.user, this.profile);

  final supabase.User user;
  final UserProfile profile;

  /// Builds the offline demo session. Only callable with the demo backend.
  factory DemoSession.create({
    required String email,
    String? displayName,
    bool isVerified = true,
  }) {
    if (!DemoBackend.active) {
      throw StateError('Demo sessions are only available in demo mode.');
    }
    final now = DateTime.now();
    final profile = UserProfile(
      id: kDemoUserId,
      displayName: displayName ?? email.split('@').first,
      email: email,
      groupId: 'grp-demo',
      currency: AppConstants.defaultCurrency,
      themeMode: 'system',
      hapticsEnabled: true,
      aiConsent: true,
      createdAt: now.subtract(const Duration(days: 30)),
      updatedAt: now,
    );
    final user = supabase.User(
      id: kDemoUserId,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: now.toIso8601String(),
      email: email,
      emailConfirmedAt: isVerified ? now.toIso8601String() : null,
    );
    return DemoSession._(user, profile);
  }

  /// Returns [user] marked as email-verified. Only callable with the demo
  /// backend.
  static supabase.User markVerified(supabase.User user) {
    if (!DemoBackend.active) {
      throw StateError('Demo sessions are only available in demo mode.');
    }
    return supabase.User(
      id: user.id,
      appMetadata: user.appMetadata,
      userMetadata: user.userMetadata,
      aud: user.aud,
      createdAt: user.createdAt,
      email: user.email,
      emailConfirmedAt: DateTime.now().toIso8601String(),
    );
  }
}
