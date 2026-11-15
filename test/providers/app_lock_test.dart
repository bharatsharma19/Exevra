import 'dart:async';

import 'package:expense_manager/core/platform/secure_window.dart';
import 'package:expense_manager/core/storage/preferences.dart';
import 'package:expense_manager/features/auth/screens/app_lock_screen.dart';
import 'package:expense_manager/features/auth/screens/login_screen.dart';
import 'package:expense_manager/features/dashboard/screens/main_navigation_shell.dart';
import 'package:expense_manager/main.dart';
import 'package:expense_manager/providers/app_lock_provider.dart';
import 'package:expense_manager/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  test('signing out keeps the flag, so signing back in is locked', () async {
    final c = await start(signedInAs: 'A', lockOn: true);
    expect(c.read(appLockProvider).showLockScreen, isTrue);
    await c.read(authControllerProvider.notifier).signOut();
    await settle();
    expect(c.read(appLockProvider).showLockScreen, isFalse);
    expect(c.read(appLockProvider).enabled, isFalse);
    expect(
      c
          .read(sharedPreferencesProvider)
          .getBool(UserPrefs.key('A', UserPrefs.appLock)),
      isTrue,
    );
    expect(secureCalls.last, isFalse);

    // Another user starts without App Lock.
    backend.auth.signInAs('B');
    await settle();
    expect(c.read(appLockProvider).enabled, isFalse);
    await c.read(authControllerProvider.notifier).signOut();
    await settle();

    // The same account straight back in with one tap is still locked.
    backend.auth.googleUserId = 'A';
    await c.read(authControllerProvider.notifier).signInWithGoogle();
    await settle();
    expect(c.read(currentUserIdProvider), 'A');
    expect(c.read(appLockProvider).showLockScreen, isTrue);
    expect(c.read(appLockProvider).canTurnOffWithoutDevice, isFalse);
    expect(secureCalls.last, isTrue);
  });

  group('a device that lost its screen lock', () {
    test('a restored session cannot turn the lock off', () async {
      localAuth.supported = false;
      final c = await start(signedInAs: 'A', lockOn: true);
      expect(c.read(appLockProvider).showLockScreen, isTrue);
      expect(c.read(appLockProvider).canTurnOffWithoutDevice, isFalse);
      expect(await lockOf(c).turnOffWithoutDevice(), isFalse);
      expect(c.read(appLockProvider).showLockScreen, isTrue);
    });

    test('a fresh sign-in may turn it off instead of being trapped', () async {
      localAuth.supported = false;
      final c = await start(signedInAs: 'A', lockOn: true);
      await c.read(authControllerProvider.notifier).signOut();
      await settle();
      backend.auth.signInAs('A');
      await settle();
      expect(c.read(appLockProvider).showLockScreen, isTrue);
      expect(c.read(appLockProvider).canTurnOffWithoutDevice, isTrue);

      expect(await lockOf(c).turnOffWithoutDevice(), isTrue);
      expect(c.read(appLockProvider).showLockScreen, isFalse);
      expect(c.read(appLockProvider).enabled, isFalse);
      expect(
        c
            .read(sharedPreferencesProvider)
            .getBool(UserPrefs.key('A', UserPrefs.appLock)),
        isFalse,
      );
      expect(secureCalls.last, isFalse);
    });

    test('a fresh sign-in on a secure device still has to unlock', () async {
      final c = await start(signedInAs: 'A', lockOn: true);
      await c.read(authControllerProvider.notifier).signOut();
      await settle();
      backend.auth.signInAs('A');
      await settle();
      expect(c.read(appLockProvider).canTurnOffWithoutDevice, isFalse);
      expect(await lockOf(c).turnOffWithoutDevice(), isFalse);
      expect(c.read(appLockProvider).showLockScreen, isTrue);
    });
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
      expect(find.text('Turn off App Lock'), findsNothing);
      await tester.tap(find.text('Sign out'));
      await tester.pump();
      expect(find.textContaining('Sign out on this device?'), findsOneWidget);
    });

    testWidgets('after a fresh sign-in an insecure device can turn it off', (
      tester,
    ) async {
      final c = await pumpGate(tester, supported: false);
      await tester.runAsync(() async {
        await c.read(authControllerProvider.notifier).signOut();
        await settle();
        backend.auth.signInAs('A');
        await settle();
      });
      await tester.pump();
      expect(find.byType(AppLockScreen), findsOneWidget);

      await tester.tap(find.text('Turn off App Lock'));
      await tester.runAsync(settle);
      await tester.pump();
      expect(find.byType(AppLockScreen), findsNothing);
      expect(find.text('Secret balance'), findsOneWidget);
    });
  });

  group('session messages', () {
    const secret = 'Rent 25,000 paid to Asha';

    Future<void> frames(WidgetTester tester, [int count = 5]) async {
      for (var i = 0; i < count; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<ProviderContainer> pumpApp(
      WidgetTester tester, {
      bool lockOn = false,
    }) async {
      tester.view.physicalSize = const Size(1800, 4800);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async => null,
          );
      final c = (await tester.runAsync(
        () => start(signedInAs: 'A', lockOn: lockOn),
      ))!;
      backend.profiles.profiles['A'] = profileOf('A');
      backend.profiles.profiles['B'] = profileOf('B');
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const ExevraApp()),
      );
      await frames(tester);
      expect(find.byType(AppLockScreen), findsNothing);
      return c;
    }

    void showSecret(WidgetTester tester) {
      ScaffoldMessenger.of(
        tester.element(find.byType(MainNavigationShell)),
      ).showSnackBar(const SnackBar(content: Text(secret)));
    }

    testWidgets('a snack bar is not visible once the app locks', (
      tester,
    ) async {
      final c = await pumpApp(tester, lockOn: true);
      showSecret(tester);
      await frames(tester);
      expect(find.text(secret), findsOneWidget);

      // Back after a long time away: the app locks (the prompt is
      // cancelled, so it stays locked).
      localAuth.answers.add(
        const LocalAuthException(code: LocalAuthExceptionCode.userCanceled),
      );
      lockOf(c).onLifecycleChanged(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 1));
      lockOf(c).onLifecycleChanged(AppLifecycleState.resumed);
      await frames(tester);

      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.text(secret), findsNothing);
    });

    testWidgets('no snack bar of A survives sign-out or reaches B', (
      tester,
    ) async {
      final c = await pumpApp(tester);
      showSecret(tester);
      await frames(tester);
      expect(find.text(secret), findsOneWidget);

      await tester.runAsync(
        () => c.read(authControllerProvider.notifier).signOut(),
      );
      await frames(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text(secret), findsNothing);

      await tester.runAsync(() async {
        backend.auth.signInAs('B');
        await settle();
      });
      await frames(tester);
      expect(c.read(currentUserIdProvider), 'B');
      expect(find.byType(MainNavigationShell), findsOneWidget);
      expect(find.text(secret), findsNothing);
    });
  });
}
