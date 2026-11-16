import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:expense_manager/features/auth/screens/email_verification_screen.dart';
import 'package:expense_manager/features/auth/screens/forgot_password_screen.dart';
import 'package:expense_manager/features/auth/screens/login_screen.dart';
import 'package:expense_manager/features/auth/screens/register_screen.dart';
import 'package:expense_manager/features/auth/screens/reset_password_screen.dart';
import 'package:expense_manager/features/auth/widgets/auth_widgets.dart';
import 'package:expense_manager/features/auth/widgets/google_sign_in_button.dart';
import 'package:expense_manager/l10n/l10n.dart';
import 'package:expense_manager/providers/auth_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../support/fakes.dart';

/// Pumps [screen] as the only route of a themed app (other locations show
/// "route:<location>").
Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget screen, {
  ThemeMode mode = ThemeMode.light,
  Size size = const Size(400, 900),
  double textScale = 1,
  TestBackend? backend,
  Future<void> Function(ProviderContainer c)? before,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  final c = (await tester.runAsync((backend ?? TestBackend()).container))!;
  addTearDown(c.dispose);
  if (before != null) await tester.runAsync(() => before(c));
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => screen)],
    errorBuilder: (_, state) => Scaffold(body: Text('route:${state.uri}')),
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return c;
}

Future<void> _signUp(ProviderContainer c) async {
  await c
      .read(authControllerProvider.notifier)
      .signUp(
        email: 'new@example.com',
        password: 'Passw0rd!',
        displayName: 'N',
      );
  await settle();
}

final _screens = <String, (Widget, Future<void> Function(ProviderContainer)?)>{
  'login': (const LoginScreen(), null),
  'register': (const RegisterScreen(), null),
  'forgot password': (const ForgotPasswordScreen(), null),
  'reset password': (const ResetPasswordScreen(), null),
  'verify email': (const EmailVerificationScreen(), _signUp),
};

void main() {
  for (final MapEntry(key: name, value: (screen, before)) in _screens.entries) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('$name meets the a11y guidelines ($mode)', (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, screen, mode: mode, before: before);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });
    }

    testWidgets('$name fits 320dp at 200% text', (tester) async {
      await _pump(
        tester,
        screen,
        size: const Size(320, 640),
        textScale: 2,
        before: before,
      );
      expect(tester.takeException(), isNull);
      // The page scrolls to its end without overflowing.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  group('login', () {
    testWidgets('shows inline errors and a friendly failure', (tester) async {
      final backend = TestBackend();
      await _pump(tester, const LoginScreen(), backend: backend);

      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pump();
      expect(find.text('Email address is required'), findsWidgets);

      backend.auth.failNext = const AppFailure.invalidCredentials();
      await tester.enterText(find.byType(TextFormField).first, 'a@example.com');
      await tester.enterText(find.byType(TextFormField).last, 'secret-pw');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.runAsync(settle);
      await tester.pump();
      expect(find.byType(AuthMessage), findsOneWidget);
    });

    testWidgets('the password toggle has a tooltip and reveals the text', (
      tester,
    ) async {
      await _pump(tester, const LoginScreen());
      expect(find.byTooltip('Show password'), findsOneWidget);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(find.byTooltip('Hide password'), findsOneWidget);
    });

    testWidgets('uses an autofill group for email and password', (
      tester,
    ) async {
      await _pump(tester, const LoginScreen());
      expect(
        find.ancestor(
          of: find.byType(TextFormField).first,
          matching: find.byType(AutofillGroup),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'offers Sign in with Apple on iOS only',
      (tester) async {
        await _pump(tester, const LoginScreen());
        final apple = find.byType(SignInWithAppleButton);
        expect(
          apple,
          defaultTargetPlatform == TargetPlatform.iOS
              ? findsOneWidget
              : findsNothing,
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets('has no Apple button on Android', (tester) async {
      await _pump(tester, const LoginScreen());
      expect(find.byType(SignInWithAppleButton), findsNothing);
    });
  });

  group('register', () {
    testWidgets('asks to accept the terms before creating the account', (
      tester,
    ) async {
      final backend = TestBackend();
      await _pump(tester, const RegisterScreen(), backend: backend);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Nia');
      await tester.enterText(fields.at(1), 'nia@example.com');
      await tester.enterText(fields.at(2), 'Passw0rd!');
      await tester.enterText(fields.at(3), 'Passw0rd!');
      final submit = find.byKey(const Key('register-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      expect(
        find.text('Please accept the Terms of Service and Privacy Policy.'),
        findsOneWidget,
      );
      expect(backend.auth.calls, isEmpty);

      await tester.ensureVisible(find.byKey(const Key('register-terms')));
      await tester.tap(find.byKey(const Key('register-terms')));
      await tester.pump();
      await tester.tap(submit);
      await tester.runAsync(settle);
      await tester.pump();
      expect(backend.auth.calls, contains('signUp:nia@example.com'));
    });

    testWidgets('links to the terms and the privacy policy', (tester) async {
      await _pump(tester, const RegisterScreen());
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
    });
  });

  group('forgot password', () {
    testWidgets('sends a code, then counts down before a resend', (
      tester,
    ) async {
      final backend = TestBackend();
      await _pump(
        tester,
        const ForgotPasswordScreen(initialEmail: 'a@example.com'),
        backend: backend,
      );
      await tester.tap(find.byKey(const Key('forgot-send')));
      await tester.runAsync(settle);
      await tester.pump();

      expect(find.text('Enter the code'), findsOneWidget);
      expect(find.textContaining('You can resend in'), findsOneWidget);
      final resend = tester.widget<TextButton>(
        find.descendant(
          of: find.byKey(const Key('forgot-resend')),
          matching: find.byWidgetPredicate((w) => w is TextButton),
        ),
      );
      expect(resend.onPressed, isNull);
    });
  });

  group('verify email', () {
    testWidgets('shows the address and the resend countdown', (tester) async {
      await _pump(tester, const EmailVerificationScreen(), before: _signUp);
      expect(find.text('new@example.com'), findsOneWidget);
      expect(find.text('Resend email'), findsOneWidget);
    });
  });

  group('resend cooldown', () {
    testWidgets('counts down, then enables the button and announces it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final announcements = <String>[];
      tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
            message,
          ) async {
            announcements.add('$message');
            return null;
          });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler<Object?>(
              SystemChannels.accessibility,
              null,
            ),
      );

      var now = DateTime(2026, 1, 1, 12);
      final at = now.add(const Duration(seconds: 2));
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ResendCooldownButton(
              label: 'Resend email',
              availableAt: at,
              now: () => now,
              onResend: () => taps++,
            ),
          ),
        ),
      );

      expect(find.text('You can resend in 0:02'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Resend available in 2 seconds'),
        findsOneWidget,
      );
      await tester.tap(find.text('Resend email'));
      expect(taps, 0);

      now = now.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('You can resend in'), findsNothing);
      expect(announcements.join(), contains('You can send a new email now.'));
      await tester.tap(find.text('Resend email'));
      expect(taps, 1);
      handle.dispose();
    });
  });

  group('Google button', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('is one labelled 48dp button ($mode)', (tester) async {
        final handle = tester.ensureSemantics();
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: mode,
            home: Scaffold(
              body: Center(child: GoogleSignInButton(onPressed: () => taps++)),
            ),
          ),
        );
        expect(find.bySemanticsLabel('Continue with Google'), findsOneWidget);
        expect(
          tester.getSize(find.byType(GoogleSignInButton)).height,
          greaterThanOrEqualTo(48),
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await tester.tap(find.byType(GoogleSignInButton));
        expect(taps, 1);
        handle.dispose();
      });
    }

    test('parses the logo path data', () {
      final bounds = parseSvgPath('M0 0L10 0V10H0Z').getBounds();
      expect(bounds, const Rect.fromLTWH(0, 0, 10, 10));
    });
  });
}
