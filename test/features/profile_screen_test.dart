import 'dart:async';

import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:expense_manager/core/widgets/widgets.dart';
import 'package:expense_manager/features/profile/screens/profile_screen.dart';
import 'package:expense_manager/features/profile/widgets/edit_profile_dialog.dart';
import 'package:expense_manager/l10n/l10n.dart';
import 'package:expense_manager/models/profile.dart';
import 'package:expense_manager/providers/app_lock_provider.dart';
import 'package:expense_manager/providers/profile_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// App Lock frozen at [initial] (the device's biometrics are not faked).
class _Lock extends AppLockController {
  _Lock(this.initial);

  final AppLockState initial;

  @override
  AppLockState build() => initial;
}

Future<void> _frames(WidgetTester tester, [int count = 6]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<(TestBackend, ProviderContainer)> _pump(
  WidgetTester tester, {
  ThemeMode mode = ThemeMode.light,
  Size size = const Size(400, 2400),
  double textScale = 1,
  AppLockState lock = const AppLockState(
    availability: LockAvailability.available,
  ),
  void Function(TestBackend backend)? setUp,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  final backend = TestBackend(signedInAs: 'u1');
  backend.profiles.profiles['u1'] = profileOf('u1');
  setUp?.call(backend);
  final c = (await tester.runAsync(
    () => backend.container(
      extraOverrides: [appLockProvider.overrideWith(() => _Lock(lock))],
    ),
  ))!;
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
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
        home: const ProfileScreen(),
      ),
    ),
  );
  await _frames(tester);
  return (backend, c);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _frames(tester);
}

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('meets the a11y guidelines ($mode)', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, mode: mode);
      expect(find.byKey(const Key('profile-header')), findsOneWidget);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  }

  testWidgets('fits 320dp at 200% text', (tester) async {
    await _pump(tester, size: const Size(320, 6000), textScale: 2);
    expect(tester.takeException(), isNull);
    // Large text swaps the segmented control for a list of choices.
    expect(find.byKey(const Key('settings-theme-dark')), findsOneWidget);
  });

  testWidgets('shows a skeleton while the profile loads', (tester) async {
    final hold = Completer<void>();
    await _pump(tester, setUp: (b) => b.reads.hold = hold);
    expect(find.byKey(const Key('profile-loading')), findsOneWidget);
    hold.complete();
    await tester.runAsync(settle);
    await _frames(tester);
    expect(find.byKey(const Key('profile-loading')), findsNothing);
    expect(find.byKey(const Key('profile-header')), findsOneWidget);
  });

  testWidgets('a failed load explains and retries', (tester) async {
    final (backend, _) = await _pump(
      tester,
      setUp: (b) => b.profiles.failFetch = const AppFailure.network(),
    );
    expect(find.byKey(const Key('profile-load-failed')), findsOneWidget);
    expect(find.text("We couldn't load your profile."), findsOneWidget);

    backend.profiles.failFetch = null;
    await _tap(tester, find.text('Retry').first);
    await tester.runAsync(settle);
    await _frames(tester);
    expect(find.byKey(const Key('profile-header')), findsOneWidget);
  });

  testWidgets('the theme control saves the choice', (tester) async {
    final (_, c) = await _pump(tester);
    await _tap(tester, find.text('Dark'));
    expect(c.read(themePreferenceProvider), ThemePreference.dark);
  });

  testWidgets('the currency picker searches and saves', (tester) async {
    final (backend, _) = await _pump(tester);
    await _tap(tester, find.byKey(const Key('settings-currency')));
    expect(find.text('Choose a currency'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('currency-search')), 'zzz');
    await tester.pump();
    expect(find.textContaining('No currency matches'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('currency-search')), 'euro');
    await tester.pump();
    await _tap(tester, find.byKey(const Key('currency-EUR')));
    await tester.runAsync(settle);
    await _frames(tester);
    expect(backend.profiles.updates.last.$2.fields['currency'], 'EUR');
  });

  testWidgets('App Lock explains why it is unavailable', (tester) async {
    await _pump(
      tester,
      lock: const AppLockState(availability: LockAvailability.unavailable),
    );
    final row = tester.widget<SwitchListTile>(
      find.descendant(
        of: find.byKey(const Key('settings-app-lock')),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(row.onChanged, isNull);
    expect(find.textContaining('Set up a screen lock'), findsOneWidget);
  });

  testWidgets('sign out asks first', (tester) async {
    final (backend, _) = await _pump(tester);
    await _tap(tester, find.byKey(const Key('profile-sign-out')));
    expect(find.text('Sign out?'), findsOneWidget);
    await _tap(tester, find.text('Cancel'));
    expect(backend.auth.signOutCalls, 0);

    await _tap(tester, find.byKey(const Key('profile-sign-out')));
    await _tap(
      tester,
      find.descendant(
        of: find.byType(ConfirmDialog),
        matching: find.text('Sign out'),
      ),
    );
    await tester.runAsync(settle);
    expect(backend.auth.signOutCalls, 1);
  });

  group('edit profile', () {
    testWidgets('checks the fields and saves', (tester) async {
      final (backend, _) = await _pump(tester);
      await _tap(tester, find.byKey(const Key('profile-edit')));
      expect(find.byType(EditProfileDialog), findsOneWidget);

      await tester.enterText(find.byKey(const Key('profile-edit-name')), ' ');
      await tester.enterText(
        find.byKey(const Key('profile-edit-photo')),
        'http://example.com/a.png',
      );
      await _tap(tester, find.byKey(const Key('profile-edit-save')));
      expect(find.text('Names must be 1 to 60 characters.'), findsOneWidget);
      expect(find.text('Use an https:// image link.'), findsOneWidget);
      expect(backend.profiles.updates, isEmpty);

      await tester.enterText(
        find.byKey(const Key('profile-edit-name')),
        'Priya',
      );
      await tester.enterText(find.byKey(const Key('profile-edit-photo')), '');
      await _tap(tester, find.byKey(const Key('profile-edit-save')));
      await tester.runAsync(settle);
      await _frames(tester);
      expect(find.byType(EditProfileDialog), findsNothing);
      expect(
        backend.profiles.updates.single.$2.fields['display_name'],
        'Priya',
      );
    });

    testWidgets('a failed save stays in the dialog', (tester) async {
      final (backend, _) = await _pump(tester);
      backend.profiles.failUpdates = const AppFailure.network();
      await _tap(tester, find.byKey(const Key('profile-edit')));
      await tester.enterText(
        find.byKey(const Key('profile-edit-name')),
        'Priya',
      );
      await _tap(tester, find.byKey(const Key('profile-edit-save')));
      await tester.runAsync(settle);
      await _frames(tester);
      expect(find.byType(EditProfileDialog), findsOneWidget);
    });

    testWidgets('cancelling with edits asks to discard', (tester) async {
      await _pump(tester);
      await _tap(tester, find.byKey(const Key('profile-edit')));
      await tester.enterText(
        find.byKey(const Key('profile-edit-name')),
        'Someone else',
      );
      await _tap(tester, find.text('Cancel'));
      expect(find.text('Discard changes?'), findsOneWidget);
      await _tap(tester, find.text('Discard'));
      expect(find.byType(EditProfileDialog), findsNothing);
    });
  });
}
