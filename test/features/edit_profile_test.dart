import 'dart:async';

import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/platform/secure_window.dart';
import 'package:expense_manager/core/router/app_router.dart';
import 'package:expense_manager/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:expense_manager/core/widgets/app_snackbar.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _success = 'Profile updated.';

Future<void> _frames(WidgetTester tester, [int count = 10]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SecureWindow.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SecureWindow.channel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

  Future<TestBackend> pumpProfile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1800, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final backend = TestBackend(signedInAs: 'A');
    backend.profiles.profiles['A'] = profileOf('A');
    final c = (await tester.runAsync(backend.container))!;
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const ExevraApp()),
    );
    await _frames(tester);
    c.read(routerProvider).go('/profile');
    await _frames(tester);
    return backend;
  }

  /// Opens the edit dialog, types [name] and taps Save.
  Future<void> saveName(WidgetTester tester, String name) async {
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await _frames(tester, 5);
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)).first,
      name,
    );
    await tester.tap(find.descendant(of: dialog, matching: find.text('Save')));
    await tester.pump();
  }

  group('UI-35: editing the profile', () {
    testWidgets('says so once the save is confirmed', (tester) async {
      final backend = await pumpProfile(tester);
      final held = Completer<void>();
      backend.profiles.heldUpdates.add(held);

      await saveName(tester, 'Ada Lovelace');
      await _frames(tester, 3);
      expect(find.byType(AlertDialog), findsNothing);
      expect(backend.profiles.updates, hasLength(1));
      // Not before the server answered.
      expect(find.text(_success), findsNothing);

      held.complete();
      await _frames(tester, 3);
      expect(find.text(_success), findsOneWidget);
      expect(backend.profiles.profiles['A']!.displayName, 'Ada Lovelace');
    });

    testWidgets('a failed save does not claim success', (tester) async {
      final backend = await pumpProfile(tester);
      backend.profiles.failUpdates = const AppFailure.network();

      await saveName(tester, 'Ada Lovelace');
      await _frames(tester, 5);
      expect(backend.profiles.updates, hasLength(1));
      expect(find.text(_success), findsNothing);
      // The error snack bar has an action, so it stays until dismissed; a
      // wrongly queued success message would only appear after it.
      // Check every frame: a 2 s message could otherwise come and go
      // between two checks.
      rootScaffoldMessengerKey.currentState?.hideCurrentSnackBar();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text(_success), findsNothing);
      }
    });
  });
}
