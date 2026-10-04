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
import 'package:expense_manager/providers/expense_provider.dart';
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

  group('10. Multi-Group Support & Data Isolation Tests', () {
    test('A user can belong to multiple groups simultaneously', () {
      final now = DateTime.now();
      final group1 = ExpenseGroup(
        id: 'grp-apartment',
        name: 'Apartment 4B',
        inviteCode: 'APT4B',
        adminId: 'user-a',
        createdAt: now,
        membersCount: 3,
      );
      final group2 = ExpenseGroup(
        id: 'grp-trip',
        name: 'Iceland Roadtrip',
        inviteCode: 'ICE2026',
        adminId: 'user-b',
        createdAt: now,
        membersCount: 4,
      );
      final group3 = ExpenseGroup(
        id: 'grp-project',
        name: 'Startup Team',
        inviteCode: 'START99',
        adminId: 'user-a',
        createdAt: now,
        membersCount: 5,
      );

      final state = ExpenseState(
        currentGroup: group1,
        userGroups: [group1, group2, group3],
      );

      expect(state.userGroups.length, 3);
      expect(state.currentGroup?.id, 'grp-apartment');
      expect(state.userGroups.map((g) => g.id), containsAll(['grp-apartment', 'grp-trip', 'grp-project']));
    });

    test('Switching active group isolates group data while preserving personal expenses', () {
      final now = DateTime.now();
      final personalExp = Expense(
        id: 'exp-personal-1',
        userId: 'user-a',
        groupId: null,
        title: 'Morning Coffee',
        amount: 5.50,
        category: 'Food',
        date: now,
        isPersonal: true,
        createdAt: now,
        updatedAt: now,
      );

      final grp1Exp = Expense(
        id: 'exp-grp1-1',
        userId: 'user-a',
        groupId: 'grp-1',
        title: 'WiFi Bill',
        amount: 60.00,
        category: 'Bills',
        date: now,
        isPersonal: false,
        createdAt: now,
        updatedAt: now,
      );

      // State when active in Group 1
      final stateGroup1 = ExpenseState(
        expenses: [personalExp, grp1Exp],
        currentGroup: ExpenseGroup(
          id: 'grp-1',
          name: 'Flatmates',
          inviteCode: 'FLAT1',
          adminId: 'user-a',
          createdAt: now,
          membersCount: 2,
        ),
      );

      expect(stateGroup1.expenses.length, 2);
      expect(stateGroup1.personalSpent, 5.50);
      expect(stateGroup1.groupSpent, 60.00);

      // When switched to personal only, group expenses are excluded from active state
      final statePersonalOnly = ExpenseState(
        expenses: [personalExp],
        currentGroup: null,
      );

      expect(statePersonalOnly.expenses.length, 1);
      expect(statePersonalOnly.personalSpent, 5.50);
      expect(statePersonalOnly.groupSpent, 0.0);
    });
  });

  group('11. Dynamic Split & Settlement Math Tests (2, 3, 4+ members)', () {
    final now = DateTime.now();

    test('Exact 2-member equal split debt calculation', () {
      final members = [
        GroupMember(id: 'm1', groupId: 'g1', userId: 'user-a', role: 'admin', displayName: 'Alice', joinedAt: now),
        GroupMember(id: 'm2', groupId: 'g1', userId: 'user-b', role: 'member', displayName: 'Bob', joinedAt: now),
      ];

      // Alice pays 100 for groceries
      final expenses = [
        Expense(
          id: 'e1',
          userId: 'user-a',
          groupId: 'g1',
          title: 'Groceries',
          amount: 100.0,
          category: 'Food',
          date: now,
          isPersonal: false,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final state = ExpenseState(
        currentGroup: ExpenseGroup(id: 'g1', name: 'Test', inviteCode: 'T1', adminId: 'user-a', createdAt: now, membersCount: 2),
        groupMembers: members,
        expenses: expenses,
      );

      final debts = state.settlements;
      expect(debts.length, 1);
      expect(debts.first.fromUserId, 'user-b');
      expect(debts.first.toUserId, 'user-a');
      expect(debts.first.amount, 50.0);
      expect(debts.first.fromUserName, 'Bob');
      expect(debts.first.toUserName, 'Alice');
    });

    test('3-member dynamic split with fair remainder distribution and greedy matching', () {
      final members = [
        GroupMember(id: 'm1', groupId: 'g1', userId: 'user-a', role: 'admin', displayName: 'Alice', joinedAt: now),
        GroupMember(id: 'm2', groupId: 'g1', userId: 'user-b', role: 'member', displayName: 'Bob', joinedAt: now),
        GroupMember(id: 'm3', groupId: 'g1', userId: 'user-c', role: 'member', displayName: 'Charlie', joinedAt: now),
      ];

      // Total spent = 100.00
      // 10000 cents ~/ 3 = 3333 cents with 1 cent remainder.
      // Alice share: 33.34, Bob share: 33.33, Charlie share: 33.33.
      // Alice paid 100.00 -> balance +66.66.
      // Bob paid 0.00 -> balance -33.33.
      // Charlie paid 0.00 -> balance -33.33.
      final expenses = [
        Expense(
          id: 'e1',
          userId: 'user-a',
          groupId: 'g1',
          title: 'Dinner',
          amount: 100.0,
          category: 'Food',
          date: now,
          isPersonal: false,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final state = ExpenseState(
        currentGroup: ExpenseGroup(id: 'g1', name: 'Trio', inviteCode: 'T3', adminId: 'user-a', createdAt: now, membersCount: 3),
        groupMembers: members,
        expenses: expenses,
      );

      final debts = state.settlements;
      expect(debts.length, 2);
      final totalSettled = debts.fold(0.0, (sum, d) => sum + d.amount);
      expect(double.parse(totalSettled.toStringAsFixed(2)), 66.66);

      for (final d in debts) {
        expect(d.toUserId, 'user-a');
        expect(d.toUserName, 'Alice');
      }
    });

    test('4-member complex multi-payer split with minimized debt transactions', () {
      final members = [
        GroupMember(id: 'm1', groupId: 'g1', userId: 'user-a', role: 'admin', displayName: 'Alice', joinedAt: now),
        GroupMember(id: 'm2', groupId: 'g1', userId: 'user-b', role: 'member', displayName: 'Bob', joinedAt: now),
        GroupMember(id: 'm3', groupId: 'g1', userId: 'user-c', role: 'member', displayName: 'Charlie', joinedAt: now),
        GroupMember(id: 'm4', groupId: 'g1', userId: 'user-d', role: 'member', displayName: 'Diana', joinedAt: now),
      ];

      // Alice paid 200, Bob paid 100, Charlie paid 60, Diana paid 0.
      // Total = 360. Each share is 90.00.
      // Alice: 200 - 90 = +110. (Creditor)
      // Bob: 100 - 90 = +10. (Creditor)
      // Charlie: 60 - 90 = -30. (Debtor)
      // Diana: 0 - 90 = -90. (Debtor)
      // Greedy match:
      // Diana (owes 90) pays Alice (owed 110) 90.
      // Alice is still owed 20.
      // Charlie (owes 30) pays Alice (owed 20) 20.
      // Charlie (owes 10) pays Bob (owed 10) 10.
      // Total transactions = 3 (strictly minimized)!
      final expenses = [
        Expense(id: 'e1', userId: 'user-a', groupId: 'g1', title: 'Hotel', amount: 200.0, category: 'Travel', date: now, isPersonal: false, createdAt: now, updatedAt: now),
        Expense(id: 'e2', userId: 'user-b', groupId: 'g1', title: 'Car Rental', amount: 100.0, category: 'Travel', date: now, isPersonal: false, createdAt: now, updatedAt: now),
        Expense(id: 'e3', userId: 'user-c', groupId: 'g1', title: 'Snacks', amount: 60.0, category: 'Food', date: now, isPersonal: false, createdAt: now, updatedAt: now),
      ];

      final state = ExpenseState(
        currentGroup: ExpenseGroup(id: 'g1', name: 'Roadtrip', inviteCode: 'ROAD', adminId: 'user-a', createdAt: now, membersCount: 4),
        groupMembers: members,
        expenses: expenses,
      );

      final debts = state.settlements;
      expect(debts.length, 3);
      final totalPaidToAlice = debts.where((d) => d.toUserId == 'user-a').fold(0.0, (sum, d) => sum + d.amount);
      final totalPaidToBob = debts.where((d) => d.toUserId == 'user-b').fold(0.0, (sum, d) => sum + d.amount);
      expect(totalPaidToAlice, 110.0);
      expect(totalPaidToBob, 10.0);
    });
  });

  group('12. Settlement Recording & Debt Offset Math Tests', () {
    final now = DateTime.now();

    test('Recorded settlement payment reduces or eliminates outstanding debt', () {
      final members = [
        GroupMember(id: 'm1', groupId: 'g1', userId: 'user-a', role: 'admin', displayName: 'Alice', joinedAt: now),
        GroupMember(id: 'm2', groupId: 'g1', userId: 'user-b', role: 'member', displayName: 'Bob', joinedAt: now),
      ];

      // Alice paid 100. Bob owes 50.
      final expenses = [
        Expense(id: 'e1', userId: 'user-a', groupId: 'g1', title: 'Electric Bill', amount: 100.0, category: 'Bills', date: now, isPersonal: false, createdAt: now, updatedAt: now),
      ];

      // Bob records a partial settlement payment of 30.00 to Alice
      final settlementPartial = Settlement(
        id: 's1',
        groupId: 'g1',
        payerId: 'user-b',
        payerName: 'Bob',
        payeeId: 'user-a',
        payeeName: 'Alice',
        amount: 30.0,
        date: now,
        notes: 'Bank transfer',
        createdAt: now,
      );

      final stateWithPartial = ExpenseState(
        currentGroup: ExpenseGroup(id: 'g1', name: 'Apartment', inviteCode: 'APT', adminId: 'user-a', createdAt: now, membersCount: 2),
        groupMembers: members,
        expenses: expenses,
        settlementHistory: [settlementPartial],
      );

      final partialDebts = stateWithPartial.settlements;
      expect(partialDebts.length, 1);
      expect(partialDebts.first.amount, 20.0);

      // Now Bob records the remaining 20.00
      final settlementFull = Settlement(
        id: 's2',
        groupId: 'g1',
        payerId: 'user-b',
        payerName: 'Bob',
        payeeId: 'user-a',
        payeeName: 'Alice',
        amount: 20.0,
        date: now,
        notes: 'Cash',
        createdAt: now,
      );

      final stateSettled = ExpenseState(
        currentGroup: ExpenseGroup(id: 'g1', name: 'Apartment', inviteCode: 'APT', adminId: 'user-a', createdAt: now, membersCount: 2),
        groupMembers: members,
        expenses: expenses,
        settlementHistory: [settlementFull, settlementPartial],
      );

      expect(stateSettled.settlements, isEmpty);
    });
  });

  group('13. Group Invitations & Cryptographic Tokens Tests', () {
    final now = DateTime.now();

    test('GroupInvitation model serialization and active state check', () {
      final inv = GroupInvitation(
        id: 'inv-101',
        groupId: 'grp-test',
        groupName: 'Fintech Squad',
        inviterId: 'user-a',
        inviterName: 'Alice',
        email: 'bob@example.com',
        role: 'member',
        token: 'cryptosecuretoken1234567890',
        status: 'pending',
        expiresAt: now.add(const Duration(days: 7)),
        createdAt: now,
      );

      expect(inv.isExpired, isFalse);
      expect(inv.status, 'pending');
      expect(inv.email, 'bob@example.com');
      expect(inv.role, 'member');

      final json = inv.toJson();
      expect(json['token'], 'cryptosecuretoken1234567890');
      expect(json['status'], 'pending');

      final deserialized = GroupInvitation.fromJson(json);
      expect(deserialized.id, 'inv-101');
      expect(deserialized.groupName, 'Fintech Squad');
      expect(deserialized.token, 'cryptosecuretoken1234567890');
    });

    test('GroupInvitation accurately identifies expired invitations', () {
      final expiredInv = GroupInvitation(
        id: 'inv-expired',
        groupId: 'grp-test',
        inviterId: 'user-a',
        email: 'charlie@example.com',
        role: 'member',
        token: 'expiredtoken123',
        status: 'pending',
        expiresAt: now.subtract(const Duration(hours: 1)),
        createdAt: now.subtract(const Duration(days: 8)),
      );

      expect(expiredInv.isExpired, isTrue);
    });
  });

  group('14. Personal Payments vs Group Expenses Outflow Tests', () {
    final now = DateTime.now();

    test('Accurately distinguishes personal payment from shared group expense', () {
      final personalPayment = Expense(
        id: 'p1',
        userId: 'user-a',
        groupId: null,
        title: 'Gym Subscription',
        amount: 45.0,
        category: 'Health',
        date: now,
        isPersonal: true,
        createdAt: now,
        updatedAt: now,
      );

      final groupExpense = Expense(
        id: 'g1',
        userId: 'user-b',
        groupId: 'grp-1',
        title: 'Dinner for 4',
        amount: 200.0,
        category: 'Food',
        date: now,
        isPersonal: false,
        createdAt: now,
        updatedAt: now,
      );

      final state = ExpenseState(
        expenses: [personalPayment, groupExpense],
      );

      expect(state.personalSpent, 45.0);
      expect(state.groupSpent, 200.0);
      expect(state.totalSpent, 245.0);

      // User A out of pocket spent is only 45.0, because the 200 was paid out of pocket by User B!
      expect(state.userTotalOutflow('user-a'), 45.0);
      // User B out of pocket spent is 200.0
      expect(state.userTotalOutflow('user-b'), 200.0);
    });
  });
}

