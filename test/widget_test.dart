import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:expense_manager/main.dart';
import 'package:expense_manager/core/constants/app_constants.dart';
import 'package:expense_manager/core/utils/currency_formatter.dart';
import 'package:expense_manager/core/utils/date_helpers.dart';
import 'package:expense_manager/core/utils/validators.dart';
import 'package:expense_manager/models/expense_model.dart';
import 'package:expense_manager/models/group_model.dart';
import 'package:expense_manager/models/user_profile.dart';
import 'package:expense_manager/providers/auth_provider.dart';
import 'package:expense_manager/providers/app_lock_provider.dart';
import 'package:expense_manager/features/auth/screens/email_verification_screen.dart';
import 'package:expense_manager/features/auth/screens/app_lock_screen.dart';
import 'package:expense_manager/services/ai_chatbot_service.dart';

void main() {
  group('1. Antigravity Core App & Theme Widget Tests', () {
    testWidgets('App renders smoothly with initial smoke test', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: AntigravityExpenseApp(),
        ),
      );

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AntigravityExpenseApp), findsOneWidget);
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });

  group('2. CurrencyFormatter Unit Tests', () {
    test('Formats standard currency amounts correctly', () {
      expect(CurrencyFormatter.format(1250.50), '₹1,250.50');
      expect(CurrencyFormatter.format(1250.50, currencyCode: 'USD'), '\$1,250.50');
      expect(CurrencyFormatter.format(500.0, currencyCode: 'EUR'), '€500.00');
      expect(CurrencyFormatter.format(99.99, currencyCode: 'GBP'), '£99.99');
      expect(CurrencyFormatter.format(15000.0, currencyCode: 'INR'), '₹15,000.00');
      expect(CurrencyFormatter.format(200.0, currencyCode: 'JPY'), '¥200.00');
    });

    test('Formats compact currency values (k and M)', () {
      expect(CurrencyFormatter.formatCompact(850.0, currencyCode: 'USD'), '\$850');
      expect(CurrencyFormatter.formatCompact(4500.0, currencyCode: 'USD'), '\$4.5k');
      expect(CurrencyFormatter.formatCompact(2500000.0, currencyCode: 'USD'), '\$2.5M');
    });

    test('Parses raw string inputs to valid double values', () {
      expect(CurrencyFormatter.parseAmount('\$1,240.75'), 1240.75);
      expect(CurrencyFormatter.parseAmount('€85.50'), 85.50);
      expect(CurrencyFormatter.parseAmount('invalid'), null);
      expect(CurrencyFormatter.parseAmount(''), null);
    });
  });

  group('3. DateHelpers Temporal Logic Tests', () {
    final now = DateTime.now();
    test('Calculates relative time correctly', () {
      expect(DateHelpers.formatRelative(now), 'Just now');
      expect(DateHelpers.formatRelative(now.subtract(const Duration(minutes: 5))), '5 mins ago');
      expect(DateHelpers.formatRelative(now.subtract(const Duration(hours: 3))), '3 hours ago');
    });

    test('Resolves temporal section headers accurately', () {
      expect(DateHelpers.getDateSectionHeader(now), 'Today');
      expect(DateHelpers.getDateSectionHeader(now.subtract(const Duration(days: 1))), 'Yesterday');
    });
  });

  group('4. Form & Security Validators Unit Tests', () {
    test('Validates email formats', () {
      expect(Validators.validateEmail('user@antigravity.io'), null);
      expect(Validators.validateEmail('invalid-email'), 'Please enter a valid email address');
      expect(Validators.validateEmail(''), 'Email address is required');
      expect(Validators.validateEmail(null), 'Email address is required');
    });

    test('Validates password complexity', () {
      expect(Validators.validatePassword('Password123'), null);
      expect(Validators.validatePassword('short1'), 'Password must be at least 8 characters long');
      expect(Validators.validatePassword('allletters'), 'Password must contain at least one number');
      expect(Validators.validatePassword('12345678'), 'Password must contain at least one letter');
      expect(Validators.validatePassword(''), 'Password is required');
    });

    test('Validates international phone numbers', () {
      expect(Validators.validatePhone('+14155552671'), null);
      expect(Validators.validatePhone('+447911123456'), null);
      expect(Validators.validatePhone('123'), 'Please enter a valid international phone (e.g. +1234567890)');
    });

    test('Validates 6-digit OTP tokens', () {
      expect(Validators.validateOtp('123456'), null);
      expect(Validators.validateOtp('12345'), 'Please enter a 6-digit code');
      expect(Validators.validateOtp('abcdef'), 'Please enter a 6-digit code');
    });

    test('Validates expense amounts', () {
      expect(Validators.validateAmount('45.99'), null);
      expect(Validators.validateAmount('0'), 'Amount must be greater than 0');
      expect(Validators.validateAmount('-10'), 'Amount must be greater than 0');
      expect(Validators.validateAmount(''), 'Amount is required');
    });
  });

  group('5. Granular Permissions Matrix Model Tests', () {
    final now = DateTime.now();
    final personalExpense = Expense(
      id: 'exp-1',
      userId: 'user-alice',
      groupId: null,
      title: 'Groceries',
      amount: 50.0,
      category: 'Food',
      date: now,
      isPersonal: true,
      createdAt: now,
      updatedAt: now,
    );

    final groupExpense = Expense(
      id: 'exp-2',
      userId: 'user-bob',
      groupId: 'grp-house',
      title: 'Broadband Bill',
      amount: 80.0,
      category: 'Utilities',
      date: now,
      isPersonal: false,
      createdAt: now,
      updatedAt: now,
    );

    test('Editing Permission: Only the expense creator can edit', () {
      expect(personalExpense.canEdit('user-alice'), isTrue);
      expect(personalExpense.canEdit('user-bob'), isFalse);
      expect(groupExpense.canEdit('user-bob'), isTrue);
      expect(groupExpense.canEdit('user-alice'), isFalse);
    });

    test('Deleting Permission: Creator deletes personal; Group Admin ONLY deletes group expense', () {
      expect(personalExpense.canDelete('user-alice', false), isTrue);
      expect(personalExpense.canDelete('user-bob', true), isFalse);
      expect(groupExpense.canDelete('user-bob', false), isFalse);
      expect(groupExpense.canDelete('user-charlie', true), isTrue);
      expect(groupExpense.canDelete('user-alice', false), isFalse);
    });

    test('Group Member Roles: Admin & Member can add expenses; Viewer is read-only pending review', () {
      final admin = GroupMember(
        id: 'gm-1',
        groupId: 'grp-1',
        userId: 'u-admin',
        role: 'admin',
        joinedAt: now,
      );
      final member = GroupMember(
        id: 'gm-2',
        groupId: 'grp-1',
        userId: 'u-member',
        role: 'member',
        joinedAt: now,
      );
      final viewer = GroupMember(
        id: 'gm-3',
        groupId: 'grp-1',
        userId: 'u-viewer',
        role: 'viewer',
        joinedAt: now,
      );

      expect(admin.canAddExpenses, isTrue);
      expect(admin.isViewerOnly, isFalse);
      expect(member.canAddExpenses, isTrue);
      expect(member.isViewerOnly, isFalse);
      expect(viewer.canAddExpenses, isFalse);
      expect(viewer.isViewerOnly, isTrue);
    });
  });

  group('6. AI Chatbot Domain Guardrails Tests', () {
    final aiService = AiChatbotService.instance;

    test('Permits valid financial and budgeting queries', () {
      expect(aiService.isFinancialQuery('How can I cut my grocery expense?'), isTrue);
      expect(aiService.isFinancialQuery('What is my biggest spending category?'), isTrue);
      expect(aiService.isFinancialQuery('Explain the 50/30/20 budget framework'), isTrue);
      expect(aiService.isFinancialQuery('How much did we spend on utilities?'), isTrue);
      expect(aiService.isFinancialQuery('Give me advice on saving money for a mortgage loan'), isTrue);
    });

    test('Rejects non-financial queries', () {
      expect(aiService.isFinancialQuery('Write a Python script to scrape a website'), isFalse);
      expect(aiService.isFinancialQuery('What is the capital of Australia?'), isFalse);
      expect(aiService.isFinancialQuery('Tell me a bedtime story about dragons'), isFalse);
    });
  });

  group('7. Email Verification Gate Unit & Widget Tests', () {
    test('AppAuthState.isEmailVerified accurately detects verification status', () {
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
        email: 'pending@antigravity.io',
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
        email: 'verified@antigravity.io',
        emailConfirmedAt: DateTime.now().toIso8601String(),
      );
      final verifiedState = AppAuthState(
        status: AuthStatus.authenticated,
        user: confirmedUser,
      );
      expect(verifiedState.isEmailVerified, isTrue);

      // Phone user without email is not gated
      final phoneUser = supabase.User(
        id: 'u-phone',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        phone: '+14155552671',
      );
      final phoneState = AppAuthState(
        status: AuthStatus.authenticated,
        user: phoneUser,
      );
      expect(phoneState.isEmailVerified, isTrue);
    });

    testWidgets('EmailVerificationScreen displays verification interface and controls', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: EmailVerificationScreen(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Verify Your Email'), findsOneWidget);
      expect(find.text("I've Verified My Email"), findsOneWidget);
      expect(find.byType(EmailVerificationScreen), findsOneWidget);
    });
  });

  group('8. App Lock & Biometrics Unit & Widget Tests', () {
    test('AppLockState transitions correctly on enable and timeout', () {
      var lockState = const AppLockState(isBiometricsEnabled: false, isLocked: false);
      expect(lockState.isLocked, isFalse);

      // User enables biometrics
      lockState = lockState.copyWith(isBiometricsEnabled: true);
      expect(lockState.isBiometricsEnabled, isTrue);

      // App backgrounded
      final pausedTime = DateTime.now().subtract(const Duration(seconds: AppConstants.lockTimeoutSeconds + 5));
      lockState = lockState.copyWith(lastBackgroundTime: pausedTime);

      final elapsed = DateTime.now().difference(lockState.lastBackgroundTime!).inSeconds;
      expect(elapsed >= AppConstants.lockTimeoutSeconds, isTrue);

      // App locked
      lockState = lockState.copyWith(isLocked: true);
      expect(lockState.isLocked, isTrue);

      // Unlocked successfully
      lockState = lockState.copyWith(isLocked: false, clearLastBackgroundTime: true);
      expect(lockState.isLocked, isFalse);
      expect(lockState.lastBackgroundTime, isNull);
    });

    testWidgets('AppLockScreen displays biometric security gate controls', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AppLockScreen(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(AppConstants.appName), findsOneWidget);
      expect(find.text('Biometric Security Protection Active'), findsOneWidget);
      expect(find.text('Unlock with Biometrics / PIN'), findsOneWidget);
    });
  });

  group('9. Profile Model & Sync Unit Tests', () {
    test('UserProfile copyWith and serialization with avatar preset', () {
      final now = DateTime.now();
      final profile = UserProfile(
        id: 'user-test-1',
        displayName: 'Elena Rostova',
        avatarUrl: 'preset:🚀',
        currency: 'EUR',
        themeMode: 'dark',
        hapticsEnabled: true,
        aiConsent: true,
        createdAt: now,
        updatedAt: now,
      );

      final json = profile.toJson();
      expect(json['display_name'], 'Elena Rostova');
      expect(json['avatar_url'], 'preset:🚀');
      expect(json['currency'], 'EUR');
      expect(json['theme_mode'], 'dark');

      final fromJson = UserProfile.fromJson(json);
      expect(fromJson.displayName, 'Elena Rostova');
      expect(fromJson.avatarUrl, 'preset:🚀');
      expect(fromJson.currency, 'EUR');

      final updated = profile.copyWith(currency: 'GBP', displayName: 'Elena R.');
      expect(updated.currency, 'GBP');
      expect(updated.displayName, 'Elena R.');
      expect(updated.avatarUrl, 'preset:🚀');
    });

    test('AppConstants contains supported currencies and settings keys', () {
      expect(AppConstants.appName, 'Exevra');
      expect(AppConstants.defaultCurrency, 'INR');
      expect(AppConstants.currencies.containsKey('INR'), isTrue);
      expect(AppConstants.currencies.containsKey('USD'), isTrue);
      expect(AppConstants.currencies.containsKey('EUR'), isTrue);
      expect(AppConstants.currencies.containsKey('GBP'), isTrue);
      expect(AppConstants.currencies.containsKey('JPY'), isTrue);
      expect(AppConstants.lockTimeoutSeconds, 30);
      expect(AppConstants.keyBiometricsEnabled, 'app_biometrics_enabled');
    });
  });
}
