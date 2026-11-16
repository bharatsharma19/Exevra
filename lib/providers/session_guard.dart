import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_failure.dart';
import '../core/logging/app_logger.dart';
import '../core/utils/haptics.dart';
import 'auth_provider.dart';
import 'failure_reporter.dart';

/// One signed-in session. Every change of the signed-in user makes a new
/// object, so signing out and back in as the same user is a new session
/// too.
final class SignedInSession {
  SignedInSession(this.userId);

  final String userId;
}

/// The current signed-in session, or null while signed out.
final signedInSessionProvider = Provider<SignedInSession?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  return userId == null ? null : SignedInSession(userId);
});

/// The session an action started in.
///
/// Notifiers outlive sessions: the same instance serves user A, then
/// (after a sign-out) user B. An action that A started may finish while B
/// is signed in, and its result is not B's. Every async action therefore
/// captures a guard when it starts and, after every `await`, checks
/// [holds] before it changes state, calls a follow-up RPC (which would run
/// with B's token) or reports a failure. When the session changed the
/// result is dropped silently (logged at debug level) and the action
/// returns [dropped].
final class SessionGuard {
  SessionGuard._(this._ref, this._session);

  /// Captures the session signed in now. [ref] returns the caller's live
  /// [Ref] (a notifier passes `() => ref`): the `Ref` of a notifier is
  /// replaced whenever it rebuilds, so a captured one would look disposed
  /// after a harmless rebuild of the same session.
  factory SessionGuard.start(Ref Function() ref) {
    final current = ref();
    return SessionGuard._(
      ref,
      current.mounted ? current.read(signedInSessionProvider) : null,
    );
  }

  /// What an action returns when its result was dropped. Nobody sees it:
  /// the screen that started the action belonged to the previous session.
  static const AppFailure dropped = AppFailure.sessionExpired();

  final Ref Function() _ref;
  final SignedInSession? _session;

  /// The user the action runs for; null when it started signed out.
  String? get userId => _session?.userId;

  /// Whether the provider is alive and the session the action started in
  /// is still the signed-in one.
  bool get isCurrent {
    final session = _session;
    if (session == null) return false;
    final ref = _ref();
    if (!ref.mounted) return false;
    return ref.read(currentUserIdProvider) == session.userId &&
        identical(ref.read(signedInSessionProvider), session);
  }

  /// [isCurrent]; when it is not, logs that the result of [action] was
  /// dropped.
  bool holds(String action) {
    if (isCurrent) return true;
    AppLogger.debug('Dropped the result of $action: the session changed');
    return false;
  }

  /// Ends [action] with [failure] while the session holds: an error
  /// haptic and, with [report], the shared failure surface. Drops it
  /// otherwise. Returns what the action returns: [failure], or [dropped].
  AppFailure fail(AppFailure failure, String action, {bool report = true}) {
    if (!holds(action)) return dropped;
    AppHaptics.error();
    if (report) _ref().read(failureReporterProvider.notifier).report(failure);
    return failure;
  }
}
