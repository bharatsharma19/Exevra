import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The app's root [ScaffoldMessenger] (given to `MaterialApp`). Snack bars
/// and banners shown anywhere in the app go through it, so they can be
/// cleared when the session ends or the app locks.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Removes every snack bar and material banner of the root messenger at
/// once (no exit animation), so nothing from a previous session, or from
/// before the app locked, stays on screen.
void clearRootMessages() {
  if (SchedulerBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks) {
    // Called while widgets build: the messenger cannot change now.
    SchedulerBinding.instance.addPostFrameCallback((_) => _clear());
    return;
  }
  _clear();
}

void _clear() {
  final messenger = rootScaffoldMessengerKey.currentState;
  if (messenger == null || !messenger.mounted) return;
  messenger
    ..clearSnackBars()
    ..removeCurrentSnackBar()
    ..clearMaterialBanners()
    ..removeCurrentMaterialBanner();
}
