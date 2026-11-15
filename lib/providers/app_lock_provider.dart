import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../core/logging/app_logger.dart';
import '../core/platform/secure_window.dart';
import '../core/storage/preferences.dart';
import '../core/utils/haptics.dart';
import 'auth_provider.dart';

/// Whether the device can authenticate the user (biometrics or a screen
/// lock PIN, pattern or password).
enum LockAvailability { unknown, available, unavailable }

@immutable
class AppLockState {
  const AppLockState({
    this.enabled = false,
    this.locked = false,
    this.availability = LockAvailability.unknown,
    this.isAuthenticating = false,
    this.messageKey,
    this.coverVisible = false,
  });

  /// App Lock is on for the signed-in user.
  final bool enabled;

  /// The app is locked until the user authenticates.
  final bool locked;

  final LockAvailability availability;
  final bool isAuthenticating;

  /// Why the last unlock did not work (a `friendlyMessageForKey` key).
  final String? messageKey;

  /// The app is inactive (app switcher, system dialog): its content is
  /// covered so it does not show in the preview.
  final bool coverVisible;

  bool get showLockScreen => enabled && locked;

  AppLockState copyWith({
    bool? enabled,
    bool? locked,
    LockAvailability? availability,
    bool? isAuthenticating,
    String? Function()? messageKey,
    bool? coverVisible,
  }) => AppLockState(
    enabled: enabled ?? this.enabled,
    locked: locked ?? this.locked,
    availability: availability ?? this.availability,
    isAuthenticating: isAuthenticating ?? this.isAuthenticating,
    messageKey: messageKey == null ? this.messageKey : messageKey(),
    coverVisible: coverVisible ?? this.coverVisible,
  );
}

/// The platform authenticator (replaced by a fake in tests).
final localAuthProvider = Provider<LocalAuthentication>(
  (ref) => LocalAuthentication(),
);

/// Clock used for the background timeout (replaced in tests).
final appLockClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// App Lock for the signed-in user.
///
/// * Only active while a user is signed in; nothing prompts while signed
///   out. The flag is per user (`u.<uid>.app_lock`) and is removed with the
///   user's other preferences on sign-out or deletion.
/// * When on, the app starts locked and locks again after
///   [relockAfter] in the background.
/// * Turning it on or off needs a successful authentication.
/// * Screenshots and the recent-apps preview are blocked while it is on.
class AppLockController extends Notifier<AppLockState> {
  static const Duration relockAfter = Duration(seconds: 30);
  static const String unlockReason = 'Unlock Exevra';

  DateTime? _backgroundedAt;

  /// The last life-cycle state reported (null before the first).
  AppLifecycleState? _lifecycle;
  String? _userId;

  LocalAuthentication get _auth => ref.read(localAuthProvider);

  @override
  AppLockState build() {
    final userId = ref.watch(currentUserIdProvider);
    _userId = userId;
    _backgroundedAt = null;
    if (userId == null) {
      unawaited(SecureWindow.setSecure(false));
      return const AppLockState();
    }
    final enabled =
        ref
            .read(sharedPreferencesProvider)
            .getBool(UserPrefs.key(userId, UserPrefs.appLock)) ??
        false;
    unawaited(SecureWindow.setSecure(enabled));
    unawaited(Future(refreshAvailability));
    return AppLockState(enabled: enabled, locked: enabled);
  }

  /// Re-checks whether the device can authenticate.
  Future<LockAvailability> refreshAvailability() async {
    LockAvailability availability;
    try {
      availability = await _auth.isDeviceSupported()
          ? LockAvailability.available
          : LockAvailability.unavailable;
    } on Object catch (e) {
      AppLogger.warn('Device authentication check failed', e.runtimeType);
      availability = LockAvailability.unavailable;
    }
    if (ref.mounted && _userId != null) {
      state = state.copyWith(availability: availability);
    }
    return availability;
  }

  /// Asks for biometrics or the device PIN. Returns null on success, or
  /// the message key of what went wrong.
  Future<String?> _authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
      return ok ? null : 'lock_failed';
    } on LocalAuthException catch (e) {
      final key = messageKeyFor(e.code);
      if (key == 'lock_no_credentials' && ref.mounted) {
        state = state.copyWith(availability: LockAvailability.unavailable);
      }
      return key;
    } on PlatformException catch (e) {
      AppLogger.warn('Device authentication failed', e.code);
      return 'lock_failed';
    } on MissingPluginException {
      return 'lock_no_credentials';
    }
  }

  /// Message key for a local_auth error code.
  @visibleForTesting
  static String messageKeyFor(LocalAuthExceptionCode code) => switch (code) {
    LocalAuthExceptionCode.userCanceled ||
    LocalAuthExceptionCode.systemCanceled ||
    LocalAuthExceptionCode.timeout ||
    LocalAuthExceptionCode.userRequestedFallback => 'lock_cancelled',
    LocalAuthExceptionCode.noCredentialsSet ||
    LocalAuthExceptionCode.noBiometricHardware ||
    LocalAuthExceptionCode.noBiometricsEnrolled => 'lock_no_credentials',
    LocalAuthExceptionCode.temporaryLockout => 'lock_temporary_lockout',
    LocalAuthExceptionCode.biometricLockout => 'lock_biometric_lockout',
    LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable =>
      'lock_hardware_busy',
    LocalAuthExceptionCode.authInProgress => 'lock_in_progress',
    LocalAuthExceptionCode.uiUnavailable => 'lock_ui_unavailable',
    _ => 'lock_failed',
  };

  /// Unlocks after a successful authentication. Returns true when the app
  /// is unlocked.
  Future<bool> unlock() async {
    if (!state.showLockScreen) return true;
    if (state.isAuthenticating) return false;
    state = state.copyWith(isAuthenticating: true, messageKey: () => null);
    final userId = _userId;
    final key = await _authenticate(unlockReason);
    if (!ref.mounted || _userId != userId) return false;
    _afterPrompt(authenticated: key == null);
    if (key == null) {
      AppHaptics.success();
      state = state.copyWith(
        locked: false,
        isAuthenticating: false,
        coverVisible: false,
      );
      return true;
    }
    state = state.copyWith(
      isAuthenticating: false,
      // Cancelling is not an error worth showing.
      messageKey: () => key == 'lock_cancelled' ? null : key,
    );
    return false;
  }

  /// Turns App Lock on or off. Both need a successful authentication.
  /// Returns null on success or the message key of the problem.
  Future<String?> setEnabled(bool enabled) async {
    final userId = _userId;
    if (userId == null) return 'lock_signed_out';
    if (state.enabled == enabled) return null;
    if (state.isAuthenticating) return 'lock_in_progress';
    if (enabled &&
        await refreshAvailability() == LockAvailability.unavailable) {
      return 'lock_no_credentials';
    }
    if (!ref.mounted || _userId != userId) return 'lock_signed_out';
    state = state.copyWith(isAuthenticating: true);
    final key = await _authenticate(
      enabled ? 'Turn on App Lock for Exevra' : 'Turn off App Lock for Exevra',
    );
    if (!ref.mounted || _userId != userId) return 'lock_signed_out';
    state = state.copyWith(isAuthenticating: false);
    _afterPrompt(authenticated: key == null);
    if (key != null) return key;
    try {
      await ref
          .read(sharedPreferencesProvider)
          .setBool(UserPrefs.key(userId, UserPrefs.appLock), enabled);
    } on Object catch (e) {
      AppLogger.warn('App Lock setting was not saved', e.runtimeType);
      return 'lock_failed';
    }
    if (!ref.mounted || _userId != userId) return 'lock_signed_out';
    state = state.copyWith(enabled: enabled, locked: false);
    await SecureWindow.setSecure(enabled);
    AppHaptics.selection();
    return null;
  }

  /// Follows the app life cycle: covers the content when inactive, notes
  /// when the app went to the background and locks again on return.
  void onLifecycleChanged(AppLifecycleState lifecycle) {
    _lifecycle = lifecycle;
    if (_userId == null || !state.enabled) return;
    final now = ref.read(appLockClockProvider)();
    if (state.isAuthenticating) {
      // The system prompt itself makes the app inactive; that is not
      // leaving the app. Time in the background still counts, and is
      // judged when the prompt ends (see [_afterPrompt]).
      if (lifecycle == AppLifecycleState.hidden ||
          lifecycle == AppLifecycleState.paused) {
        _backgroundedAt ??= now;
      }
      return;
    }
    switch (lifecycle) {
      case AppLifecycleState.inactive:
        state = state.copyWith(coverVisible: true);
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _backgroundedAt ??= now;
        state = state.copyWith(coverVisible: true);
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        final relock = since != null && now.difference(since) >= relockAfter;
        state = state.copyWith(
          coverVisible: false,
          locked: state.locked || relock,
          messageKey: relock ? () => null : null,
        );
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Applies the relock rule to time spent in the background while a
  /// prompt was open. A successful authentication is fresh proof of
  /// presence; after a cancel the app locks if it was away long enough.
  /// While still in the background, the next resume decides instead.
  void _afterPrompt({required bool authenticated}) {
    if (authenticated) {
      _backgroundedAt = null;
      return;
    }
    final lifecycle = _lifecycle;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null || !state.enabled) return;
    final now = ref.read(appLockClockProvider)();
    if (now.difference(since) >= relockAfter) {
      state = state.copyWith(locked: true, coverVisible: false);
    }
  }
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(
  AppLockController.new,
);
