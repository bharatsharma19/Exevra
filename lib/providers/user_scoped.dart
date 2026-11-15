import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_failure.dart';
import 'auth_provider.dart';
import 'session_guard.dart';

export 'session_guard.dart';

/// Data that belongs to the signed-in user, loaded asynchronously.
///
/// Riverpod's `AsyncNotifier` and `FutureProvider` keep the previous value
/// while they rebuild, and after a rebuild fails. For one user's data that
/// would show user A's data while B's loads, or after B's load failed.
/// This notifier holds a plain [AsyncValue] instead:
///
/// * When the signed-in user changes, the state is [AsyncLoading] without
///   any value, and a failed load is an [AsyncError] without any value.
/// * A rebuild for the same user (a retry, a data revision) keeps showing
///   that user's loaded data until the new data arrives.
/// * Only the latest load changes the state; a load for an earlier user
///   or an earlier rebuild is dropped.
///
/// [owner] is the user whose data the state holds.
abstract class UserScopedNotifier<T> extends Notifier<AsyncValue<T>> {
  int _loads = 0;
  String? _owner;
  bool _loading = false;
  Completer<T>? _waiting;

  /// The user whose data (or failure) the state holds; null while signed
  /// out or while nothing has loaded for the signed-in user yet.
  String? get owner => _owner;

  /// Whether a (re)load is on its way; its result will replace the state.
  bool get isReloading => _loading;

  /// The state while signed out.
  AsyncValue<T> whenSignedOut();

  /// Loads the data of [userId]. It runs inside `build` up to its first
  /// `await`, so `ref.watch` calls before that are dependencies.
  Future<T> fetch(String userId);

  /// The user [value] belongs to, when the value records it. A value that
  /// names another user is never applied.
  String? ownerOf(T value) => null;

  /// Called after the data of [userId] was applied.
  void onLoaded(String userId, T value) {}

  /// The session an action of this notifier starts in. Every async action
  /// captures one first and checks [SessionGuard.holds] after each
  /// `await`, before it changes the state, calls a follow-up RPC or
  /// reports a failure (see [SessionGuard]).
  SessionGuard guard() => SessionGuard.start(() => ref);

  @override
  AsyncValue<T> build() {
    final userId = ref.watch(currentUserIdProvider);
    final load = ++_loads;
    final previous = stateOrNull;
    if (userId == null) {
      _owner = null;
      _loading = false;
      final signedOut = whenSignedOut();
      _settleWaiting(signedOut);
      return signedOut;
    }
    final keep = _owner == userId && previous is AsyncData<T>;
    _loading = true;
    Future<T> future;
    try {
      future = fetch(userId);
    } on Object catch (error, stackTrace) {
      future = Future.error(error, stackTrace);
    }
    unawaited(
      future.then(
        (value) {
          final owner = ownerOf(value);
          if (owner != null && owner != userId) {
            _finish(
              load,
              userId,
              AsyncError(const AppFailure.sessionExpired(), StackTrace.current),
            );
            return;
          }
          if (_finish(load, userId, AsyncData(value))) onLoaded(userId, value);
        },
        onError: (Object error, StackTrace stackTrace) =>
            _finish(load, userId, AsyncError(error, stackTrace)),
      ),
    );
    if (keep) return previous;
    _owner = null;
    return AsyncLoading<T>();
  }

  /// Applies the result of [load] when it is still the latest.
  bool _finish(int load, String userId, AsyncValue<T> result) {
    if (load != _loads || !ref.mounted) return false;
    _loading = false;
    _owner = userId;
    state = result;
    _settleWaiting(result);
    return true;
  }

  void _settleWaiting(AsyncValue<T> result) {
    final waiting = _waiting;
    if (waiting == null) return;
    switch (result) {
      case AsyncData(:final value):
        _waiting = null;
        waiting.complete(value);
      case AsyncError(:final error, :final stackTrace):
        _waiting = null;
        waiting.completeError(error, stackTrace);
      case AsyncLoading():
        break;
    }
  }

  /// The data once the current load has finished (what `.future` is for
  /// an `AsyncNotifier`); it fails with the load's failure.
  Future<T> get loaded {
    // Reading the state runs a pending rebuild first.
    final current = state;
    if (_loading) {
      return (_waiting ??= Completer<T>()..future.ignore()).future;
    }
    return switch (current) {
      AsyncData(:final value) => Future.value(value),
      AsyncError(:final error, :final stackTrace) => Future.error(
        error,
        stackTrace,
      ),
      AsyncLoading() => (_waiting ??= Completer<T>()..future.ignore()).future,
    };
  }
}

/// A [UserScopedNotifier] for a one-off read (what a `FutureProvider`
/// would be): [load] runs for the signed-in user. Signed out it fails with
/// "session expired" so nothing stale is shown.
class UserScopedFuture<T> extends UserScopedNotifier<T> {
  UserScopedFuture(this.load);

  final Future<T> Function(Ref ref, String userId) load;

  @override
  AsyncValue<T> whenSignedOut() =>
      const AsyncError(AppFailure.sessionExpired(), StackTrace.empty);

  @override
  Future<T> fetch(String userId) => load(ref, userId);
}
