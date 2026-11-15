import 'dart:async';

import 'package:expense_manager/core/platform/secure_window.dart';
import 'package:expense_manager/core/storage/preferences.dart';
import 'package:expense_manager/features/auth/screens/app_lock_screen.dart';
import 'package:expense_manager/main.dart';
import 'package:expense_manager/providers/app_lock_provider.dart';
import 'package:expense_manager/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

import '../support/fakes.dart';

/// Device authentication with scripted answers.
class FakeLocalAuth implements LocalAuthentication {
  bool supported = true;

  /// Next results: true/false, a [LocalAuthException] to throw, or a
  /// [Completer] whose result is the answer (a prompt left open).
  final List<Object> answers = [];
  final List<String> reasons = [];

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object?> authMessages = const [],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    reasons.add(localizedReason);
    expect(biometricOnly, isFalse, reason: 'device PIN must be allowed');
    final answer = answers.isEmpty ? true : answers.removeAt(0);
    if (answer is Completer<bool>) return answer.future;
    if (answer is LocalAuthException) throw answer;
    return answer as bool;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestBackend backend;
  late FakeLocalAuth localAuth;
  late DateTime now;
  final secureCalls = <bool>[];

  setUp(() {
    localAuth = FakeLocalAuth();
    now = DateTime(2026, 11, 15, 10);
    secureCalls.clear();
    SecureWindow.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SecureWindow.channel, (call) async {
          if (call.method == 'setSecure') {
            secureCalls.add((call.arguments as Map)['enabled'] as bool);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SecureWindow.channel, null),
    );
  });

  Future<ProviderContainer> start({
    String? signedInAs,
    bool lockOn = false,
  }) async {
    backend = TestBackend(signedInAs: signedInAs);
    final container = await backend.container(
      prefs: {
        if (signedInAs != null && lockOn)
          UserPrefs.key(signedInAs, UserPrefs.appLock): true,
      },
      extraOverrides: [
        localAuthProvider.overrideWithValue(localAuth),
        appLockClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    container.listen(appLockProvider, (_, _) {});
    await settle();
    return container;
  }

  AppLockController lockOf(ProviderContainer c) =>
      c.read(appLockProvider.notifier);

  test('nothing is locked or prompted while signed out', () async {
    final c = await start();
    expect(c.read(appLockProvider).showLockScreen, isFalse);
    expect(await lockOf(c).setEnabled(true), 'lock_signed_out');
    lockOf(c).onLifecycleChanged(AppLifecycleState.inactive);
    expect(c.read(appLockProvider).coverVisible, isFalse);
    expect(localAuth.reasons, isEmpty);
  });

  test(
    'starts locked on a cold start when on, and blocks screenshots',
    () async {
      final c = await start(signedInAs: 'A', lockOn: true);
      expect(c.read(appLockProvider).showLockScreen, isTrue);
      expect(secureCalls.last, isTrue);

      expect(await lockOf(c).unlock(), isTrue);
      expect(localAuth.reasons, ['Unlock Exevra']);
      expect(c.read(appLockProvider).showLockScreen, isFalse);
    },
  );

  group('time in the background while a prompt is open', () {
    Future<(ProviderContainer, Completer<bool>, Future<String?>)> leaveDuring(
      Duration away,
    ) async {
      final c = await start(signedInAs: 'A', lockOn: true);
      expect(await lockOf(c).unlock(), isTrue);
      final prompt = Completer<bool>();
      localAuth.answers.add(prompt);
      final turningOff = lockOf(c).setEnabled(false);
      await settle();
      expect(c.read(appLockProvider).isAuthenticating, isTrue);

      // The user leaves the app with the prompt open, then comes back.
      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        lockOf(c).onLifecycleChanged(s);
      }
      now = now.add(away);
      for (final s in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        lockOf(c).onLifecycleChanged(s);
      }
      return (c, prompt, turningOff);
    }

    test('cancelling after a long absence locks the app', () async {
      final (c, prompt, turningOff) = await leaveDuring(
        const Duration(minutes: 5),
      );
      prompt.completeError(
        const LocalAuthException(code: LocalAuthExceptionCode.userCanceled),
      );
      expect(await turningOff, 'lock_cancelled');
      expect(c.read(appLockProvider).enabled, isTrue);
      expect(c.read(appLockProvider).showLockScreen, isTrue);
    });

    test('cancelling after a short absence stays unlocked', () async {
      final (c, prompt, turningOff) = await leaveDuring(
        const Duration(seconds: 5),
      );
      prompt.complete(false);
      expect(await turningOff, 'lock_failed');
      expect(c.read(appLockProvider).showLockScreen, isFalse);
    });

    test('authenticating on return counts as presence', () async {
      final (c, prompt, turningOff) = await leaveDuring(
        const Duration(minutes: 5),
      );
      prompt.complete(true);
      expect(await turningOff, isNull);
      expect(c.read(appLockProvider).enabled, isFalse);
      expect(c.read(appLockProvider).showLockScreen, isFalse);
    });
  });

  test('cancelling the prompt stays locked without an error', () async {
    final c = await start(signedInAs: 'A', lockOn: true);
    localAuth.answers.add(
      const LocalAuthException(code: LocalAuthExceptionCode.userCanceled),
    );
    expect(await lockOf(c).unlock(), isFalse);
    expect(c.read(appLockProvider).showLockScreen, isTrue);
    expect(c.read(appLockProvider).messageKey, isNull);
  });

  test('errors map to accurate messages', () {
    expect(
      AppLockController.messageKeyFor(LocalAuthExceptionCode.noCredentialsSet),
      'lock_no_credentials',
    );
    expect(
      AppLockController.messageKeyFor(LocalAuthExceptionCode.temporaryLockout),
      'lock_temporary_lockout',
    );
    expect(
      AppLockController.messageKeyFor(LocalAuthExceptionCode.biometricLockout),
      'lock_biometric_lockout',
    );
    expect(
      AppLockController.messageKeyFor(LocalAuthExceptionCode.uiUnavailable),
      'lock_ui_unavailable',
    );
    expect(
      AppLockController.messageKeyFor(LocalAuthExceptionCode.deviceError),
      'lock_failed',
    );
  });

  test('enabling and disabling both need authentication', () async {
    final c = await start(signedInAs: 'A');
    localAuth.answers.add(false);
    expect(await lockOf(c).setEnabled(true), 'lock_failed');
    expect(c.read(appLockProvider).enabled, isFalse);

    expect(await lockOf(c).setEnabled(true), isNull);
    expect(c.read(appLockProvider).enabled, isTrue);
    expect(c.read(appLockProvider).locked, isFalse);
    expect(
      c
          .read(sharedPreferencesProvider)
          .getBool(UserPrefs.key('A', UserPrefs.appLock)),
      isTrue,
    );
    expect(secureCalls.last, isTrue);

    localAuth.answers.add(
      const LocalAuthException(code: LocalAuthExceptionCode.userCanceled),
    );
    expect(await lockOf(c).setEnabled(false), 'lock_cancelled');
    expect(c.read(appLockProvider).enabled, isTrue);

    expect(await lockOf(c).setEnabled(false), isNull);
    expect(c.read(appLockProvider).enabled, isFalse);
    expect(secureCalls.last, isFalse);
    expect(localAuth.reasons, hasLength(4));
  });

  test('cannot be turned on without device security', () async {
    localAuth.supported = false;
    final c = await start(signedInAs: 'A');
    expect(c.read(appLockProvider).availability, LockAvailability.unavailable);
    expect(await lockOf(c).setEnabled(true), 'lock_no_credentials');
    expect(localAuth.reasons, isEmpty);
  });

  test('relocks after 30 s in the background, covers when inactive', () async {
    final c = await start(signedInAs: 'A');
    await lockOf(c).setEnabled(true);
    final lock = lockOf(c);

    lock.onLifecycleChanged(AppLifecycleState.inactive);
    expect(c.read(appLockProvider).coverVisible, isTrue);
    lock
      ..onLifecycleChanged(AppLifecycleState.hidden)
      ..onLifecycleChanged(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 10));
    lock.onLifecycleChanged(AppLifecycleState.resumed);
    expect(c.read(appLockProvider).coverVisible, isFalse);
    expect(c.read(appLockProvider).showLockScreen, isFalse);

    lock.onLifecycleChanged(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 31));
    lock.onLifecycleChanged(AppLifecycleState.resumed);
    expect(c.read(appLockProvider).showLockScreen, isTrue);
  });

  test('signing out resets the lock and the per-user flag', () async {
    final c = await start(signedInAs: 'A', lockOn: true);
    await c.read(authControllerProvider.notifier).signOut();
    await settle();
    expect(c.read(appLockProvider).showLockScreen, isFalse);
    expect(c.read(appLockProvider).enabled, isFalse);
    expect(
      c
          .read(sharedPreferencesProvider)
          .getBool(UserPrefs.key('A', UserPrefs.appLock)),
      isNull,
    );
    expect(secureCalls.last, isFalse);

    // The next user starts without App Lock.
    backend.auth.signInAs('B');
    await settle();
    expect(c.read(appLockProvider).enabled, isFalse);
  });

  group('lock gate', () {
    Future<ProviderContainer> pumpGate(
      WidgetTester tester, {
      bool supported = true,
    }) async {
      localAuth.supported = supported;
      // Keep the prompt from succeeding so the lock stays up.
      localAuth.answers.add(
        const LocalAuthException(code: LocalAuthExceptionCode.userCanceled),
      );
      final c = await tester.runAsync(
        () => start(signedInAs: 'A', lockOn: true),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c!,
          child: const MaterialApp(
            home: LockGate(child: Scaffold(body: Text('Secret balance'))),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return c;
    }

    testWidgets('hides the app from semantics while locked', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpGate(tester);
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.bySemanticsLabel('Secret balance'), findsNothing);
      expect(find.text('Unlock'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('offers sign-out when the device has no security', (
      tester,
    ) async {
      await pumpGate(tester, supported: false);
      expect(find.text('Unlock'), findsNothing);
      expect(find.textContaining('Set up a screen lock'), findsOneWidget);
      await tester.tap(find.text('Sign out'));
      await tester.pump();
      expect(find.textContaining('Sign out on this device?'), findsOneWidget);
    });
  });
}
