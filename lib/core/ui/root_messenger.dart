import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../widgets/app_snackbar.dart';

// The app's root ScaffoldMessenger key (given to `MaterialApp`) is the
// design system's one: snack bars and banners shown anywhere in the app,
// including AppSnackbar's, go through it, so they can be cleared when the
// session ends or the app locks.
export '../widgets/app_snackbar.dart' show rootScaffoldMessengerKey;

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

/// A message waiting for the sign-in screen (see [showOnSignIn]).
typedef SignInNotice = ({String message, AppSnackbarKind kind});

/// The message [showOnSignIn] queued; the app shows it once the sign-in
/// screen has come in, and drops it when someone signs in.
final ValueNotifier<SignInNotice?> signInNotice = ValueNotifier(null);

/// Shows [message] on the sign-in screen once it has come in. Messages
/// shown while the session ends are cleared with the session's own, so
/// a message about the ending itself ("Your account was deleted.") goes
/// through here.
void showOnSignIn(
  String message, {
  AppSnackbarKind kind = AppSnackbarKind.info,
}) => signInNotice.value = (message: message, kind: kind);
