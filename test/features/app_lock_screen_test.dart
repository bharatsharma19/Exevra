import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:expense_manager/features/auth/screens/app_lock_screen.dart';
import 'package:expense_manager/l10n/l10n.dart';
import 'package:expense_manager/providers/app_lock_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A lock controller frozen at [initial]; counts unlock requests.
class _Lock extends AppLockController {
  _Lock(this.initial);

  final AppLockState initial;
  int unlocks = 0;

  @override
  AppLockState build() => initial;

  @override
  Future<bool> unlock() async {
    unlocks++;
    return false;
  }
}

const _locked = AppLockState(
  enabled: true,
  locked: true,
  availability: LockAvailability.available,
);

Future<_Lock> _pump(
  WidgetTester tester,
  AppLockState state, {
  ThemeMode mode = ThemeMode.light,
  Size size = const Size(400, 860),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final lock = _Lock(state);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appLockProvider.overrideWith(() => lock)],
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const AppLockScreen(),
      ),
    ),
  );
  await tester.pump();
  return lock;
}

void main() {
  final states = {
    'locked': _locked,
    'checking': const AppLockState(
      enabled: true,
      locked: true,
      availability: LockAvailability.available,
      isAuthenticating: true,
    ),
    'failed': const AppLockState(
      enabled: true,
      locked: true,
      availability: LockAvailability.available,
      messageKey: 'lock_failed',
    ),
    'no screen lock': const AppLockState(
      enabled: true,
      locked: true,
      availability: LockAvailability.unavailable,
    ),
    'no screen lock, just signed in': const AppLockState(
      enabled: true,
      locked: true,
      availability: LockAvailability.unavailable,
      signedInHere: true,
    ),
  };

  for (final MapEntry(key: name, value: state) in states.entries) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('$name meets the a11y guidelines ($mode)', (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, state, mode: mode);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });
    }

    testWidgets('$name fits 320dp at 200% text', (tester) async {
      await _pump(tester, state, size: const Size(320, 640), textScale: 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('prompts once on open and Unlock asks again', (tester) async {
    final lock = await _pump(tester, _locked);
    expect(lock.unlocks, 1);
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    expect(lock.unlocks, 2);
  });

  testWidgets('shows why the last unlock failed', (tester) async {
    await _pump(tester, states['failed']!);
    expect(
      find.text("We couldn't confirm it's you. Please try again."),
      findsOneWidget,
    );
  });

  testWidgets('says it is checking while the prompt is open', (tester) async {
    await _pump(tester, states['checking']!);
    expect(find.text("Checking it's you…"), findsOneWidget);
  });

  testWidgets('Sign out instead asks first, inline', (tester) async {
    await _pump(tester, _locked);
    await tester.tap(find.text('Sign out instead'));
    await tester.pump();
    expect(find.textContaining('Sign out on this device?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.textContaining('Sign out on this device?'), findsNothing);
  });

  testWidgets('the privacy cover has a screen reader label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const PrivacyCover()),
    );
    expect(
      find.bySemanticsLabel('Exevra is hidden while in the background'),
      findsOneWidget,
    );
    handle.dispose();
  });
}
