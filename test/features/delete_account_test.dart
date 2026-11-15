import 'dart:async';

import 'package:expense_manager/core/platform/secure_window.dart';
import 'package:expense_manager/core/router/app_router.dart';
import 'package:expense_manager/data/repositories/account_repository.dart';
import 'package:expense_manager/features/auth/screens/login_screen.dart';
import 'package:expense_manager/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

class _Accounts implements AccountRepository {
  int calls = 0;

  @override
  Future<void> deleteAccount({String? appleAuthorizationCode}) async {
    calls++;
  }
}

/// Pumps frames without waiting for animations to settle (the progress
/// dialog spins).
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

  testWidgets('a slow sign-out after deletion still ends on sign-in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final backend = TestBackend(signedInAs: 'A');
    backend.profiles.profiles['A'] = profileOf('A');
    final accounts = _Accounts();
    final c = (await tester.runAsync(
      () => backend.container(
        extraOverrides: [accountRepositoryProvider.overrideWithValue(accounts)],
      ),
    ))!;
    addTearDown(c.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const ExevraApp()),
    );
    await _frames(tester);
    c.read(routerProvider).go('/profile');
    await _frames(tester);

    final delete = find.text('Delete Account');
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await _frames(tester);

    // The server part of the sign-out is slow: the app is already on the
    // sign-in screen when it ends.
    final hold = Completer<void>();
    backend.auth.holdSignOut = hold;
    await tester.tap(find.text('Delete account'));
    await _frames(tester);
    expect(accounts.calls, 1);
    expect(find.byType(LoginScreen), findsOneWidget);

    hold.complete();
    await _frames(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Deleting your account...'), findsNothing);
    expect(
      c.read(routerProvider).routerDelegate.currentConfiguration.uri.path,
      '/login',
    );
    expect(find.text('Your account was deleted.'), findsOneWidget);
  });
}
