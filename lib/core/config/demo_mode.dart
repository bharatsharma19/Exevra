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

/// True only for the offline demo account inside a demo build. Permission
/// shortcuts for the demo account depend on this, so they never apply in
/// release builds.
bool isDemoUser(String? userId) => kDemoMode && userId == kDemoUserId;

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

  /// Builds the offline demo session. Only callable in demo mode.
  factory DemoSession.create({
    required String email,
    String? displayName,
    String? phone,
    bool isVerified = true,
  }) {
    if (!kDemoMode) {
      throw StateError('Demo sessions are only available in demo mode.');
    }
    final now = DateTime.now();
    final profile = UserProfile(
      id: kDemoUserId,
      displayName: displayName ?? email.split('@').first,
      email: email,
      phone: phone,
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
      phone: phone,
      emailConfirmedAt: isVerified ? now.toIso8601String() : null,
    );
    return DemoSession._(user, profile);
  }

  /// Returns [user] marked as email-verified. Only callable in demo mode.
  static supabase.User markVerified(supabase.User user) {
    if (!kDemoMode) {
      throw StateError('Demo sessions are only available in demo mode.');
    }
    return supabase.User(
      id: user.id,
      appMetadata: user.appMetadata,
      userMetadata: user.userMetadata,
      aud: user.aud,
      createdAt: user.createdAt,
      email: user.email,
      phone: user.phone,
      emailConfirmedAt: DateTime.now().toIso8601String(),
    );
  }
}
