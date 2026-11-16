import 'dart:async';

import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/errors/failure_messages.dart';
import 'package:expense_manager/core/router/app_router.dart';
import 'package:expense_manager/core/router/navigation.dart';
import 'package:expense_manager/features/auth/screens/forgot_password_screen.dart';
import 'package:expense_manager/features/auth/screens/login_screen.dart';
import 'package:expense_manager/features/auth/screens/register_screen.dart';
import 'package:expense_manager/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../support/fakes.dart';

/// Pumps frames without waiting for endless animations (spinners).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The app, signed out, on the sign-in screen (or [location]).
Future<(TestBackend, ProviderContainer)> _pumpSignedOut(
  WidgetTester tester, {
  String? location,
}) async {
  // Tall enough that the whole form is on screen.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final backend = TestBackend();
  final container = (await tester.runAsync(backend.container))!;
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ExevraApp()),
  );
  await _settle(tester);
  if (location != null) {
    container.read(routerProvider).go(location);
    await _settle(tester);
  }
  return (backend, container);
}

String _location(ProviderContainer c) =>
    c.read(routerProvider).routerDelegate.currentConfiguration.uri.toString();

Finder _inside(Type screen, Finder finder) =>
    find.descendant(of: find.byType(screen), matching: finder);

void main() {
  group('STORE-09: Sign in with Apple', () {
    testWidgets(
      'is not offered on Android',
      (tester) async {
        await _pumpSignedOut(tester);
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(showAppleSignIn, isFalse);
        expect(find.byType(SignInWithAppleButton), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets('is offered on iOS only', (tester) async {
      await _pumpSignedOut(tester);
      final iOS = debugDefaultTargetPlatformOverride == TargetPlatform.iOS;
      expect(showAppleSignIn, iOS);
      expect(
        find.byType(SignInWithAppleButton),
        iOS ? findsOneWidget : findsNothing,
      );
    }, variant: TargetPlatformVariant.all());
  });

  group('AUTH-17: going back', () {
    Future<GoRouter> pumpRouter(
      WidgetTester tester, {
      required String initialLocation,
    }) async {
      final router = GoRouter(
        initialLocation: initialLocation,
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Text('home')),
          GoRoute(path: '/other', builder: (_, _) => const Text('other')),
          GoRoute(
            path: '/child',
            builder: (context, _) => TextButton(
              onPressed: () => popOrGo(context, '/'),
              child: const Text('back'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('popOrGo goes to the fallback when nothing can be popped', (
      tester,
    ) async {
      final router = await pumpRouter(tester, initialLocation: '/child');
      expect(router.canPop(), isFalse);

      await tester.tap(find.text('back'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('home'), findsOneWidget);
      expect(router.state.uri.toString(), '/');
    });

    testWidgets('popOrGo pops when there is a screen below', (tester) async {
      // The screen below ('/other') differs from the fallback ('/'), so a
      // real pop and a fallback navigation land on different screens.
      final router = await pumpRouter(tester, initialLocation: '/other');
      unawaited(router.push('/child'));
      await tester.pumpAndSettle();
      expect(router.canPop(), isTrue);

      await tester.tap(find.text('back'));
      await tester.pumpAndSettle();
      expect(find.text('other'), findsOneWidget);
      expect(find.text('home'), findsNothing);
      expect(router.canPop(), isFalse);
    });

    testWidgets('Back on registration opened by a link goes to sign-in', (
      tester,
    ) async {
      final (_, container) = await _pumpSignedOut(
        tester,
        location: '/register',
      );
      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(container.read(routerProvider).canPop(), isFalse);

      await tester.tap(_inside(RegisterScreen, find.byType(BackButton)));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(_location(container), '/login');
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('AUTH-27: auth errors stay on their screen', () {
    final message = friendlyMessage(const AppFailure.invalidCredentials());

    Future<TestBackend> failSignIn(WidgetTester tester) async {
      final (backend, _) = await _pumpSignedOut(tester);
      backend.auth.failNext = const AppFailure.invalidCredentials();
      final fields = _inside(LoginScreen, find.byType(EditableText));
      await tester.enterText(fields.at(0), 'a@example.com');
      await tester.enterText(fields.at(1), 'wrong-password');
      await tester.tap(_inside(LoginScreen, find.text('Sign in')).last);
      await _settle(tester);
      expect(backend.auth.calls, contains('signIn:a@example.com'));
      expect(_inside(LoginScreen, find.text(message)), findsOneWidget);
      return backend;
    }

    testWidgets('a sign-in error is not shown on registration', (tester) async {
      await failSignIn(tester);
      await tester.tap(_inside(LoginScreen, find.text('Sign up')));
      await _settle(tester);
      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(_inside(RegisterScreen, find.text(message)), findsNothing);
      expect(find.text(message), findsNothing);
    });

    testWidgets('a sign-in error is not shown on password reset', (
      tester,
    ) async {
      await failSignIn(tester);
      await tester.tap(_inside(LoginScreen, find.text('Forgot password?')));
      await _settle(tester);
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
      expect(_inside(ForgotPasswordScreen, find.text(message)), findsNothing);
      expect(find.text(message), findsNothing);
    });

    testWidgets('editing the form clears the sign-in error', (tester) async {
      await failSignIn(tester);
      await tester.enterText(
        _inside(LoginScreen, find.byType(EditableText)).at(1),
        'another-try',
      );
      await tester.pump();
      expect(find.text(message), findsNothing);
    });
  });
}
