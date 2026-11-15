import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/haptics.dart';

class AppLockState {
  final bool isBiometricsEnabled;
  final bool isLocked;
  final bool canCheckBiometrics;
  final bool isAuthenticating;
  final String? errorMessage;
  final DateTime? lastBackgroundTime;

  const AppLockState({
    this.isBiometricsEnabled = false,
    this.isLocked = false,
    this.canCheckBiometrics = false,
    this.isAuthenticating = false,
    this.errorMessage,
    this.lastBackgroundTime,
  });

  AppLockState copyWith({
    bool? isBiometricsEnabled,
    bool? isLocked,
    bool? canCheckBiometrics,
    bool? isAuthenticating,
    Object? errorMessage = const Object(),
    DateTime? lastBackgroundTime,
    bool clearLastBackgroundTime = false,
  }) {
    return AppLockState(
      isBiometricsEnabled: isBiometricsEnabled ?? this.isBiometricsEnabled,
      isLocked: isLocked ?? this.isLocked,
      canCheckBiometrics: canCheckBiometrics ?? this.canCheckBiometrics,
      isAuthenticating: isAuthenticating ?? this.isAuthenticating,
      errorMessage: errorMessage == const Object()
          ? this.errorMessage
          : errorMessage as String?,
      lastBackgroundTime: clearLastBackgroundTime
          ? null
          : (lastBackgroundTime ?? this.lastBackgroundTime),
    );
  }
}

class AppLockNotifier extends StateNotifier<AppLockState> {
  final LocalAuthentication _localAuth;
  final FlutterSecureStorage _secureStorage;

  AppLockNotifier({
    LocalAuthentication? localAuth,
    FlutterSecureStorage? secureStorage,
  }) : _localAuth = localAuth ?? LocalAuthentication(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       super(const AppLockState()) {
    unawaited(init());
  }

  Future<void> init() async {
    bool canCheck = false;
    bool enabled = false;

    try {
      final isSupported = await _localAuth.isDeviceSupported();
      final hasBiometrics = await _localAuth.canCheckBiometrics;
      canCheck = isSupported || hasBiometrics;
    } catch (e) {
      debugPrint('[AppLockNotifier] Biometrics capability check notice: $e');
      canCheck = false;
    }

    try {
      final storedVal = await _secureStorage.read(
        key: AppConstants.keyBiometricsEnabled,
      );
      enabled = storedVal == 'true';
    } catch (e) {
      debugPrint('[AppLockNotifier] Secure storage read notice: $e');
      enabled = false;
    }

    state = state.copyWith(
      canCheckBiometrics: canCheck,
      isBiometricsEnabled: enabled,
      isLocked: enabled, // Cold launch locks if enabled
    );

    if (enabled) {
      // Prompt on cold launch
      await authenticate();
    }
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    try {
      await _secureStorage.write(
        key: AppConstants.keyBiometricsEnabled,
        value: enabled ? 'true' : 'false',
      );
      state = state.copyWith(isBiometricsEnabled: enabled, isLocked: false);
      AppHaptics.selection();
    } catch (e) {
      debugPrint(
        '[AppLockNotifier] Error persisting biometrics preference: $e',
      );
    }
  }

  Future<bool> authenticate({String? customReason}) async {
    if (state.isAuthenticating) return false;

    state = state.copyWith(isAuthenticating: true, errorMessage: null);

    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: customReason ?? 'Authenticate to access Exevra',
        persistAcrossBackgrounding: true,
      );

      if (authenticated) {
        state = state.copyWith(
          isLocked: false,
          isAuthenticating: false,
          errorMessage: null,
          clearLastBackgroundTime: true,
        );
        AppHaptics.success();
        return true;
      } else {
        _onAuthenticationCancelled();
        return false;
      }
    } on LocalAuthException catch (e) {
      if (e.code == LocalAuthExceptionCode.userCanceled ||
          e.code == LocalAuthExceptionCode.systemCanceled ||
          e.code == LocalAuthExceptionCode.timeout) {
        _onAuthenticationCancelled();
        return false;
      }
      _onAuthenticationUnavailable(e);
      return false;
    } catch (e) {
      _onAuthenticationUnavailable(e);
      return false;
    }
  }

  void _onAuthenticationCancelled() {
    state = state.copyWith(
      isAuthenticating: false,
      errorMessage: 'Authentication was cancelled or failed.',
    );
    AppHaptics.error();
  }

  void _onAuthenticationUnavailable(Object error) {
    debugPrint('[AppLockNotifier] LocalAuth exception: $error');
    state = state.copyWith(
      isAuthenticating: false,
      errorMessage:
          'Biometric authentication unavailable. Use device PIN/Passcode.',
    );
  }

  void onAppPaused() {
    state = state.copyWith(lastBackgroundTime: DateTime.now());
  }

  void onAppResumed() {
    if (!state.isBiometricsEnabled) return;

    final lastPaused = state.lastBackgroundTime;
    if (lastPaused == null) {
      // First resume or already tracked
      return;
    }

    final elapsedSeconds = DateTime.now().difference(lastPaused).inSeconds;
    if (elapsedSeconds >= AppConstants.lockTimeoutSeconds) {
      state = state.copyWith(isLocked: true);
      unawaited(authenticate());
    }
  }

  void unlockDirectly() {
    state = state.copyWith(isLocked: false, errorMessage: null);
  }

  void lockImmediately() {
    if (state.isBiometricsEnabled) {
      state = state.copyWith(isLocked: true);
    }
  }
}

final appLockProvider = StateNotifierProvider<AppLockNotifier, AppLockState>((
  ref,
) {
  return AppLockNotifier();
});
