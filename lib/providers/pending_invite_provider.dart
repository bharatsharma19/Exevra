import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';
import '../core/router/deep_links.dart';
import '../core/storage/preferences.dart';
import 'auth_provider.dart';

/// An invitation opened before the user could act on it (signed out, not
/// verified yet, or the app was closed). It is kept on the device, so it
/// survives a cold start and the sign-in, and is opened once the user is
/// signed in. It is dropped when a signed-in user leaves.
class PendingInviteNotifier extends Notifier<String?> {
  static const String prefKey = 'pending_invite_token';

  @override
  String? build() {
    ref.listen<String?>(currentUserIdProvider, (previous, next) {
      if (previous != null && previous != next) clear();
    });
    final stored = ref.read(sharedPreferencesProvider).getString(prefKey);
    return DeepLinks.isValidToken(stored) ? stored : null;
  }

  void set(String token) {
    if (!DeepLinks.isValidToken(token) || state == token) return;
    state = token;
    _write(token);
  }

  void clear() {
    if (state == null) return;
    state = null;
    _write(null);
  }

  void _write(String? token) {
    final prefs = ref.read(sharedPreferencesProvider);
    unawaited(
      (token == null ? prefs.remove(prefKey) : prefs.setString(prefKey, token))
          .then<void>(
            (_) {},
            onError: (Object e) {
              AppLogger.warn('Pending invitation not saved', e.runtimeType);
            },
          ),
    );
  }
}

final pendingInviteProvider = NotifierProvider<PendingInviteNotifier, String?>(
  PendingInviteNotifier.new,
);
