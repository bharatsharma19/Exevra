import 'dart:async';

import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/platform/secure_window.dart';
import 'package:expense_manager/core/router/app_router.dart';
import 'package:expense_manager/core/widgets/widgets.dart';
import 'package:expense_manager/data/repositories/account_repository.dart';
import 'package:expense_manager/features/auth/screens/login_screen.dart';
import 'package:expense_manager/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

class _Accounts implements AccountRepository {
  int calls = 0;

  /// Thrown (once each) by the next calls, like the server's answer to a
  /// session without a recent sign-in.
  final List<AppFailure> failures = [];

  @override
  Future<void> deleteAccount({String? appleAuthorizationCode}) async {
    calls++;
    if (failures.isNotEmpty) throw failures.removeAt(0);
  }
}

/// The confirm button of the deletion dialog.
final _confirm = find.descendant(
  of: find.byType(ConfirmDialog),
  matching: find.text('Delete account'),
);

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

  late TestBackend backend;
  late _Accounts accounts;
  late ProviderContainer c;

  /// Opens Profile as A and confirms Delete account (the deletion starts
  /// once [confirm] is tapped by the caller).
  Future<void> openDeletion(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1800, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    backend = TestBackend(signedInAs: 'A');
    backend.profiles.profiles['A'] = profileOf('A');
    accounts = _Accounts();
    c = (await tester.runAsync(
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

    final delete = find.byKey(const Key('profile-delete-account'));
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await _frames(tester);
  }

  String path() =>
      c.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

  testWidgets('an old session signs in again, then the deletion runs', (
    tester,
  ) async {
    await openDeletion(tester);
    accounts.failures.add(const AppFailure.business('reauth_required'));

    await tester.tap(_confirm);
    await _frames(tester);
    expect(accounts.calls, 1);
    expect(find.text("Confirm it's you"), findsOneWidget);

    await tester.enterText(find.byKey(const Key('reauth-password')), 'pw-1');
    await tester.tap(find.byKey(const Key('reauth-continue')));
    await _frames(tester);

    expect(backend.auth.calls, contains('reauth:password:pw-1'));
    expect(accounts.calls, 2);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(path(), '/login');
    expect(backend.auth.signOutCalls, 1);
  });

  testWidgets('cancelling the sign-in keeps the account', (tester) async {
    await openDeletion(tester);
    accounts.failures.add(const AppFailure.business('reauth_required'));

    await tester.tap(_confirm);
    await _frames(tester);
    await tester.tap(find.text('Cancel'));
    await _frames(tester);

    expect(accounts.calls, 1);
    expect(backend.auth.signOutCalls, 0);
    expect(path(), '/profile');
    expect(find.textContaining('Nothing was deleted'), findsOneWidget);
  });

  testWidgets('a wrong password keeps the account', (tester) async {
    await openDeletion(tester);
    accounts.failures.add(const AppFailure.business('reauth_required'));
    backend.auth.reauthFailure = const AppFailure.invalidCredentials();

    await tester.tap(_confirm);
    await _frames(tester);
    await tester.enterText(find.byKey(const Key('reauth-password')), 'bad');
    await tester.tap(find.byKey(const Key('reauth-continue')));
    await _frames(tester);

    expect(accounts.calls, 1);
    expect(backend.auth.signOutCalls, 0);
    expect(path(), '/profile');
    expect(find.text("Checking it's you…"), findsNothing);
  });

  testWidgets('a slow sign-out after deletion still ends on sign-in', (
    tester,
  ) async {
    await openDeletion(tester);

    // The server part of the sign-out is slow: the app is already on the
    // sign-in screen when it ends.
    final hold = Completer<void>();
    backend.auth.holdSignOut = hold;
    await tester.tap(_confirm);
    await _frames(tester);
    expect(accounts.calls, 1);
    expect(find.byType(LoginScreen), findsOneWidget);

    hold.complete();
    await _frames(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Deleting your account…'), findsNothing);
    expect(path(), '/login');
    expect(find.text('Your account was deleted.'), findsOneWidget);
  });
}
