import 'package:expense_manager/core/constants/app_constants.dart';
import 'package:expense_manager/core/utils/validators.dart';
import 'package:expense_manager/features/auth/screens/app_lock_screen.dart';
import 'package:expense_manager/features/auth/screens/email_verification_screen.dart';
import 'package:expense_manager/main.dart';
import 'package:expense_manager/providers/app_lock_provider.dart';
import 'package:expense_manager/providers/auth_provider.dart';
import 'package:expense_manager/providers/chat_provider.dart';
import 'package:expense_manager/services/ai_chat_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'support/fakes.dart';

void main() {
  group('1. Exevra Core App & Theme Widget Tests', () {
    testWidgets('App renders smoothly with initial smoke test', (
      WidgetTester tester,
    ) async {
      final container = await TestBackend().container();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ExevraApp(),
        ),
      );

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ExevraApp), findsOneWidget);
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });

  group('4. Form & Security Validators Unit Tests', () {
    test('Validates email formats', () {
      expect(Validators.validateEmail('user@example.com'), null);
      expect(Validators.validateEmail('first+tag@example.co.in'), null);
      expect(Validators.validateEmail('a@example.travel'), null);
      expect(
        Validators.validateEmail('invalid-email'),
        'Please enter a valid email address',
      );
      expect(Validators.validateEmail(''), 'Email address is required');
      expect(Validators.validateEmail(null), 'Email address is required');
    });

    test('Validates password complexity', () {
      expect(Validators.validatePassword('Password123'), null);
      expect(
        Validators.validatePassword('short1'),
        'Password must be at least 8 characters long',
      );
      expect(
        Validators.validatePassword('allletters'),
        'Password must contain at least one number',
      );
      expect(
        Validators.validatePassword('12345678'),
        'Password must contain at least one letter',
      );
      expect(Validators.validatePassword(''), 'Password is required');
    });

    test('Validates 6-digit OTP tokens', () {
      expect(Validators.validateOtp('123456'), null);
      expect(Validators.validateOtp('12345'), 'Please enter a 6-digit code');
      expect(Validators.validateOtp('abcdef'), 'Please enter a 6-digit code');
    });
  });

  group('6. Assistant Availability Tests', () {
    test('Unavailable assistant fails with a friendly typed message', () async {
      const service = UnavailableAiChatService();
      await expectLater(
        service.ask('How can I cut my grocery expense?'),
        throwsA(
          isA<AiUnavailable>().having(
            (f) => f.userMessage,
            'userMessage',
            'The assistant is getting an upgrade. Please check back soon.',
          ),
        ),
      );
    });

    test('Chat shows the friendly message instead of a fake answer', () async {
      final container = await TestBackend(signedInAs: 'u1').container();
      addTearDown(container.dispose);

      await container.read(chatProvider.notifier).sendMessage('Hello');
      final messages = container.read(chatProvider).messages;

      expect(messages.last.isUser, isFalse);
      expect(messages.last.isStreaming, isFalse);
      expect(
        messages.last.text,
        'The assistant is getting an upgrade. Please check back soon.',
      );
      expect(container.read(chatProvider).isGenerating, isFalse);
    });
  });

  group('7. Email Verification Gate Unit & Widget Tests', () {
    test(
      'AppAuthState.isEmailVerified accurately detects verification status',
      () {
        // Unauthenticated state
        const unauthState = AppAuthState(status: AuthStatus.unauthenticated);
        expect(unauthState.isEmailVerified, isFalse);

        // Authenticated with unconfirmed email
        final unconfirmedUser = supabase.User(
          id: 'u-1',
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: DateTime.now().toIso8601String(),
          email: 'pending@example.com',
          emailConfirmedAt: null,
        );
        final unverifiedState = AppAuthState(
          status: AuthStatus.authenticated,
          user: unconfirmedUser,
        );
        expect(unverifiedState.isEmailVerified, isFalse);

        // Authenticated with confirmed email
        final confirmedUser = supabase.User(
          id: 'u-1',
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: DateTime.now().toIso8601String(),
          email: 'verified@example.com',
          emailConfirmedAt: DateTime.now().toIso8601String(),
        );
        final verifiedState = AppAuthState(
          status: AuthStatus.authenticated,
          user: confirmedUser,
        );
        expect(verifiedState.isEmailVerified, isTrue);
      },
    );

    testWidgets(
      'EmailVerificationScreen displays verification interface and controls',
      (WidgetTester tester) async {
        final container = await TestBackend().container();
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: EmailVerificationScreen()),
          ),
        );

        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Verify Your Email'), findsOneWidget);
        expect(find.text("I've Verified My Email"), findsOneWidget);
        expect(find.byType(EmailVerificationScreen), findsOneWidget);
      },
    );
  });

  group('8. App Lock & Biometrics Unit & Widget Tests', () {
    test('AppLockState transitions correctly on enable and timeout', () {
      var lockState = const AppLockState(
        isBiometricsEnabled: false,
        isLocked: false,
      );
      expect(lockState.isLocked, isFalse);

      // User enables biometrics
      lockState = lockState.copyWith(isBiometricsEnabled: true);
      expect(lockState.isBiometricsEnabled, isTrue);

      // App backgrounded
      final pausedTime = DateTime.now().subtract(
        const Duration(seconds: AppConstants.lockTimeoutSeconds + 5),
      );
      lockState = lockState.copyWith(lastBackgroundTime: pausedTime);

      final elapsed = DateTime.now()
          .difference(lockState.lastBackgroundTime!)
          .inSeconds;
      expect(elapsed >= AppConstants.lockTimeoutSeconds, isTrue);

      // App locked
      lockState = lockState.copyWith(isLocked: true);
      expect(lockState.isLocked, isTrue);

      // Unlocked successfully
      lockState = lockState.copyWith(
        isLocked: false,
        clearLastBackgroundTime: true,
      );
      expect(lockState.isLocked, isFalse);
      expect(lockState.lastBackgroundTime, isNull);
    });

    testWidgets('AppLockScreen displays biometric security gate controls', (
      WidgetTester tester,
    ) async {
      final container = await TestBackend().container();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AppLockScreen()),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(AppConstants.appName), findsOneWidget);
      expect(find.text('Biometric Security Protection Active'), findsOneWidget);
      expect(find.text('Unlock with Biometrics / PIN'), findsOneWidget);
    });
  });
}
