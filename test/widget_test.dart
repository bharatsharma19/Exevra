import 'package:expense_manager/core/utils/validators.dart';
import 'package:expense_manager/core/widgets/app_snackbar.dart';
import 'package:expense_manager/l10n/l10n.dart';
import 'package:expense_manager/main.dart';
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

    testWidgets('wires localizations, the root messenger and the snack bar '
        'host below the lock gate', (tester) async {
      final container = await TestBackend().container();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ExevraApp(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.scaffoldMessengerKey, same(rootScaffoldMessengerKey));
      expect(app.localizationsDelegates, contains(AppLocalizations.delegate));
      expect(app.supportedLocales, AppLocalizations.supportedLocales);
      expect(
        find.ancestor(
          of: find.byType(SnackbarHost),
          matching: find.byType(LockGate),
        ),
        findsOneWidget,
      );

      AppSnackbar.showInfo('Saved for later');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.descendant(
          of: find.byType(SnackbarHost),
          matching: find.text('Saved for later'),
        ),
        findsOneWidget,
      );
      rootScaffoldMessengerKey.currentState?.clearSnackBars();
      await tester.pump(const Duration(seconds: 1));
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

    test('Validates 8-digit OTP tokens', () {
      expect(Validators.validateOtp('12345678'), null);
      expect(Validators.validateOtp('123456'), 'Please enter an 8-digit code');
      expect(
        Validators.validateOtp('abcdefgh'),
        'Please enter an 8-digit code',
      );
    });
  });
}
