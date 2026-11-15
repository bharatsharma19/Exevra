import 'package:expense_manager/core/utils/validators.dart';
import 'package:expense_manager/main.dart';
import 'package:expense_manager/providers/chat_provider.dart';
import 'package:expense_manager/services/ai_chat_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
