import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';

/// Whether the device has a network connection, and changes to it.
///
/// This only knows about the device's network interfaces; a connected
/// network can still fail to reach the server, so requests keep their own
/// error handling.
abstract interface class ConnectivitySource {
  Future<bool> isOnline();
  Stream<bool> get changes;
}

/// [ConnectivitySource] backed by connectivity_plus.
class PlusConnectivitySource implements ConnectivitySource {
  PlusConnectivitySource([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static bool _online(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  Future<bool> isOnline() async =>
      _online(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get changes =>
      _connectivity.onConnectivityChanged.map(_online).distinct();
}

final connectivitySourceProvider = Provider<ConnectivitySource>(
  (ref) => PlusConnectivitySource(),
);

/// True while the device has a network connection. Assumes online until
/// the platform answers, and when it cannot (so no false offline banner).
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final source = ref.watch(connectivitySourceProvider);
  try {
    yield await source.isOnline();
  } on MissingPluginException {
    yield true;
    return;
  } on PlatformException catch (error) {
    AppLogger.warn('Connectivity check failed', error.code);
    yield true;
  }
  yield* source.changes.handleError((Object error) {
    AppLogger.warn('Connectivity updates failed', error.runtimeType);
  });
});

/// Synchronous view of [isOnlineProvider] (online while unknown).
final isOfflineProvider = Provider<bool>(
  (ref) => !(ref.watch(isOnlineProvider).value ?? true),
);
