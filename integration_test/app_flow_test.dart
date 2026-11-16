// End-to-end happy path on a device against the LOCAL Supabase stack:
// sign-up with the emailed code, a personal expense, a group with a second
// member (driven over REST), balances and a confirmed settlement, the AI
// assistant, the dark theme, sign-out/sign-in and account deletion.
//
// Needs: `supabase start`, `supabase functions serve --env-file
// supabase/functions/.env`, an emulator, and (for screenshots) the host
// helper `python3 integration_test/screenshot_server.py <out_dir>`. Run:
//
//   flutter test integration_test/app_flow_test.dart -d emulator-5554 \
//     --dart-define-from-file=config/local.json \
//     --dart-define=E2E_SERVICE_KEY=<local SERVICE_ROLE_KEY>
//
// The service key is the local stack's and is used only by the test
// support code (creating and removing the second user); never by lib/.
import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/errors/failure_messages.dart';
import 'package:expense_manager/data/ai/ai_chat_models.dart';
import 'package:expense_manager/features/auth/widgets/auth_widgets.dart';
import 'package:expense_manager/l10n/l10n.dart';
import 'package:expense_manager/main.dart' as app;
import 'package:expense_manager/models/money.dart';
import 'package:expense_manager/core/utils/money_format.dart';
import 'package:expense_manager/providers/chat_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/backend.dart';
import 'support/driver.dart';
import 'support/e2e_env.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Frames run as in the real app; the helpers wait in real time.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('happy path on the local stack', (tester) async {
    expect(E2eEnv.problems, isEmpty, reason: E2eEnv.problems.join(' '));

    final l10n = lookupAppLocalizations(const Locale('en'));
    final shots = Screens(tester);
    final log = StepLog(
      onFail: (step) => shots.current('failed_${_slug(step)}', keyboard: true),
    );
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final email = 'e2e.$stamp@example.test';
    final friendEmail = 'e2e.friend.$stamp@example.test';
    const password = 'E2e-Passw0rd!x';
    const name = 'E2E Tester';
    const friendName = 'E2E Friend';
    final groupName = 'E2E Flat $stamp';
    RestUser? friend;

    // Errors the app reports through FlutterError (layout overflow,
    // exceptions in build) are collected and fail the run at the end.
    final flutterErrors = <String>[];
    final testOnError = FlutterError.onError;

    try {
      // ---- 1. Fresh install -> onboarding -> sign-up -> verified ----------
      await log.step('fresh start shows onboarding', () async {
        // As after a fresh install: no preferences, so the keystore is
        // cleared too (SecureSessionStorage.clearAfterReinstall).
        await (await SharedPreferences.getInstance()).clear();
        await app.main();
        final appOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          flutterErrors.add(details.toString());
          appOnError?.call(details);
        };
        await waitFor(
          tester,
          find.text(l10n.onboardingSkip),
          timeout: const Duration(seconds: 40),
        );
        await shots.both('onboarding');
      });

      await log.step('skip onboarding -> login', () async {
        await tapOn(tester, find.text(l10n.onboardingSkip));
        await waitFor(tester, find.byKey(const Key('login-submit')));
        await shots.both('login');
      });

      await log.step('sign up with terms', () async {
        await tapOn(tester, find.text(l10n.authSignUp));
        await waitFor(tester, find.byKey(const Key('register-submit')));
        final fields = find.byType(TextFormField);
        await typeInto(tester, fields.at(0), name);
        await typeInto(tester, fields.at(1), email);
        await typeInto(tester, fields.at(2), password);
        await typeInto(tester, fields.at(3), password);
        await tapOn(tester, find.byKey(const Key('register-terms')));
        await shots.both('register');
        await tapOn(tester, find.byKey(const Key('register-submit')));
        await waitFor(
          tester,
          find.byKey(const Key('verify-code')),
          timeout: const Duration(seconds: 30),
        );
        await shots.both('verify_email');
      });

      await log.step('enter the emailed code -> signed in', () async {
        final code = await MailCatcher().waitForCode(email);
        await typeInto(tester, find.byType(OtpField), code);
        await tapOn(tester, find.byKey(const Key('verify-code')));
        await waitFor(
          tester,
          find.byType(NavigationBar),
          timeout: const Duration(seconds: 30),
        );
        expect(Supabase.instance.client.auth.currentUser?.email, email);
        await shots.both('home_new_user');
      });

      // ---- 2. Personal expense -------------------------------------------
      const coffee = 'E2E Coffee beans';
      await log.step('add a personal expense (249.75)', () async {
        await goToTab(tester, l10n.shellNavExpenses);
        await tapOn(tester, find.byKey(const Key('expenses-add')));
        await waitFor(tester, find.byKey(const Key('expense-save')));
        await typeInto(tester, find.byKey(const Key('expense-title')), coffee);
        await typeInto(
          tester,
          find.byKey(const Key('expense-amount')),
          '249.75',
        );
        await shots.both('add_expense', keyboard: true);
        await tapOn(tester, find.byKey(const Key('expense-save')));
        await waitForGone(tester, find.byKey(const Key('expense-save')));
        await waitFor(tester, find.text(coffee));
        expect(find.textContaining('249.75'), findsWidgets);
        await shots.both('expenses_list');
      });

      await log.step('the expense shows on Home', () async {
        await goToTab(tester, l10n.shellNavHome);
        await waitFor(tester, find.text(coffee));
        expect(find.textContaining('249.75'), findsWidgets);
        await shots.both('home_with_expense');
      });

      // ---- 3. Group, invitation, balances, settlement ---------------------
      await log.step('create an INR group', () async {
        await goToTab(tester, l10n.shellNavProfile);
        await tapOn(tester, find.byKey(const Key('groups-create')));
        await typeInto(tester, find.byKey(const Key('group-name')), groupName);
        if (find.text('INR (₹)').evaluate().isEmpty) {
          await tapOn(tester, find.byKey(const Key('group-currency')));
          await tapOn(tester, find.text('INR (₹)').last);
        }
        expect(find.text('INR (₹)'), findsOneWidget);
        await tapOn(tester, find.byKey(const Key('group-create')));
        await waitFor(tester, find.byKey(const Key('active-group-card')));
        expect(find.text(groupName), findsWidgets);
        await shots.both('group_created');
      });

      late String inviteToken;
      await log.step('invite by email -> share fallback', () async {
        await tapOn(tester, find.text(l10n.groupsInviteByEmail));
        await typeInto(
          tester,
          find.byKey(const Key('invite-email')),
          friendEmail,
        );
        await tapOn(tester, find.byKey(const Key('invite-send')));
        // Email is not configured locally: send-invite says sent:false and
        // the app offers the link instead.
        await waitFor(
          tester,
          find.byKey(const Key('invite-share-link')),
          timeout: const Duration(seconds: 30),
        );
        await shots.both('invite_share_link');
        final link = tester
            .widget<SelectableText>(find.byKey(const Key('invite-share-link')))
            .data!;
        inviteToken = Uri.parse(link).pathSegments.last;
        expect(inviteToken.length, greaterThanOrEqualTo(20));
        await tapOn(tester, find.text(l10n.groupsCopyLink));
        await waitForGone(tester, find.byKey(const Key('invite-share-link')));
      });

      late String groupId;
      await log.step(
        'second user accepts (REST) and shows as member',
        () async {
          friend = await RestUser.create(
            email: friendEmail,
            password: password,
            displayName: friendName,
          );
          groupId = await friend!.acceptInvitation(inviteToken);
          final member = find.textContaining(friendName);
          if (!await appears(
            tester,
            member,
            timeout: const Duration(seconds: 8),
          )) {
            await pullToRefresh(tester, find.byKey(const Key('profile-list')));
          }
          await waitFor(tester, member);
          // Accepted: no longer listed as a pending invitation.
          await waitForGone(
            tester,
            find.textContaining(friendEmail),
            timeout: const Duration(seconds: 10),
          );
          await shots.both('group_with_member');
        },
      );

      const groceries = 'E2E Groceries';
      await log.step('group expense 500.00 paid by user 1', () async {
        await goToTab(tester, l10n.shellNavExpenses);
        await tapOn(tester, find.byKey(const Key('expenses-add')));
        await waitFor(tester, find.byKey(const Key('expense-save')));
        // The active group is the default scope.
        await waitFor(tester, find.byKey(const Key('expense-currency-locked')));
        await typeInto(
          tester,
          find.byKey(const Key('expense-title')),
          groceries,
        );
        await typeInto(tester, find.byKey(const Key('expense-amount')), '500');
        await shots.both('add_group_expense', keyboard: true);
        await tapOn(tester, find.byKey(const Key('expense-save')));
        await waitForGone(tester, find.byKey(const Key('expense-save')));
        await waitFor(tester, find.text(groceries));
      });

      final half = MoneyFormat.format(Money(25000, 'INR'));
      await log.step('balances: second user owes half ($half)', () async {
        await goToTab(tester, l10n.shellNavProfile);
        final owes = find.text(l10n.settleMemberOwes(friendName, half));
        if (!await appears(tester, owes, timeout: const Duration(seconds: 6))) {
          await pullToRefresh(tester, find.byKey(const Key('profile-list')));
        }
        await waitFor(tester, owes);
        expect(find.text(l10n.settleYouAreOwed(half)), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('settlements-card')));
        await shots.both('balances_owed');
      });

      late String settlementId;
      await log.step(
        'second user records a payment; user 1 confirms',
        () async {
          settlementId = await friend!.recordSettlement(
            groupId: groupId,
            toUser: Supabase.instance.client.auth.currentUser!.id,
            amountMinor: 25000,
          );
          final confirm = find.byKey(Key('settlement-confirm-$settlementId'));
          if (!await appears(
            tester,
            confirm,
            timeout: const Duration(seconds: 8),
          )) {
            await pullToRefresh(tester, find.byKey(const Key('profile-list')));
          }
          await waitFor(tester, confirm);
          expect(find.textContaining(l10n.settlePendingForYou), findsOneWidget);
          await tester.ensureVisible(confirm);
          await shots.both('settlement_pending');
          await tapOn(tester, confirm);
          await tapOn(
            tester,
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text(l10n.settleConfirmAction),
            ),
          );
          await waitFor(tester, find.byKey(const Key('settled-up')));
          await waitFor(
            tester,
            find.text(l10n.settleMemberSettled(friendName)),
          );
          await tester.ensureVisible(find.byKey(const Key('settled-up')));
          await shots.both('settled_up');
        },
      );

      // ---- 4. AI assistant -----------------------------------------------
      await log.step('assistant: consent, question, streamed answer', () async {
        await goToTab(tester, l10n.shellNavAssistant);
        final allow = find.text(l10n.chatConsentAllow);
        if (await appears(tester, allow)) {
          await shots.both('assistant_consent');
          await tapOn(tester, allow);
        }
        final input = find.byType(TextField);
        await waitFor(tester, input);
        await typeInto(tester, input.last, 'How much did I spend on food?');
        await tapOn(
          tester,
          find.byTooltip(l10n.chatSend),
          after: const Duration(milliseconds: 100),
        );
        final container = appContainer(tester);
        ChatMessage? answer() {
          final messages = container.read(chatProvider).messages;
          return messages.isEmpty || messages.last.isUser
              ? null
              : messages.last;
        }

        await waitUntil(
          tester,
          () {
            final a = answer();
            return a != null && !a.isStreaming;
          },
          timeout: const Duration(seconds: 60),
          reason: 'the assistant to finish answering',
        );
        final a = answer()!;
        expect(a.status, ChatMessageStatus.done, reason: '${a.errorCode}');
        expect(a.text.trim(), isNotEmpty);
        expect(a.provider, isNotNull);
        expect(
          find.textContaining(a.provider!.label),
          findsWidgets,
          reason: 'provider label',
        );
        expect(AiProvider.values, contains(a.provider));
        await waitForGone(tester, find.byTooltip(l10n.chatStop));
        await shots.both('assistant_answer');
        debugPrint(
          'E2E_AI provider=${a.provider!.label} chars=${a.text.length}',
        );
      });

      // ---- 5. Main screens in light, then dark from Settings -------------
      await log.step('main screens in light', () async {
        for (final tab in [
          l10n.shellNavHome,
          l10n.shellNavExpenses,
          l10n.shellNavInsights,
          l10n.shellNavAssistant,
          l10n.shellNavProfile,
        ]) {
          await goToTab(tester, tab);
          await settle(tester, const Duration(seconds: 1));
          await shots.current('main_${_slug(tab)}');
        }
      });

      await log.step('switch to dark in Settings', () async {
        // A segmented button, or a list on narrow screens / large text.
        final segmented = find.descendant(
          of: find.byKey(const Key('settings-theme')),
          matching: find.text(l10n.settingsThemeDark),
        );
        await tapOn(
          tester,
          segmented.evaluate().isNotEmpty
              ? segmented
              : find.byKey(const Key('settings-theme-dark')),
        );
        await waitUntil(tester, () => isDark(tester), reason: 'the dark theme');
        await shots.current('settings_dark');
        for (final tab in [
          l10n.shellNavHome,
          l10n.shellNavExpenses,
          l10n.shellNavInsights,
          l10n.shellNavAssistant,
          l10n.shellNavProfile,
        ]) {
          await goToTab(tester, tab);
          await settle(tester, const Duration(seconds: 1));
          await shots.current('main_${_slug(tab)}');
        }
      });

      // ---- 6. Sign out, sign in, delete the account -----------------------
      await log.step('sign out', () async {
        await tapOn(tester, find.byKey(const Key('profile-sign-out')));
        await tapOn(
          tester,
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(l10n.settingsSignOut),
          ),
        );
        await waitFor(tester, find.byKey(const Key('login-submit')));
        expect(Supabase.instance.client.auth.currentUser, isNull);
        await shots.both('signed_out');
      });

      Future<void> signIn() async {
        final fields = find.byType(TextFormField);
        await typeInto(tester, fields.at(0), email);
        await typeInto(tester, fields.at(1), password);
        await tapOn(tester, find.byKey(const Key('login-submit')));
      }

      await log.step('sign back in', () async {
        await signIn();
        await waitFor(
          tester,
          find.byType(NavigationBar),
          timeout: const Duration(seconds: 30),
        );
        // The app returns to the tab the user signed out from; Home shows
        // the group, still the active scope.
        await goToTab(tester, l10n.shellNavHome);
        await waitFor(tester, find.text(groceries));
        await shots.both('signed_back_in');
      });

      await log.step('delete the account from About', () async {
        await goToTab(tester, l10n.shellNavProfile);
        await tapOn(tester, find.byKey(const Key('profile-about')));
        await tapOn(tester, find.text(l10n.aboutDeleteAccount));
        await shots.both('delete_confirm');
        await tapOn(
          tester,
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(l10n.settingsDeleteAccount),
          ),
        );
        // A sign-in older than 10 minutes needs the password again.
        final reauth = find.byKey(const Key('reauth-password'));
        final login = find.byKey(const Key('login-submit'));
        await waitUntil(
          tester,
          () => reauth.evaluate().isNotEmpty || login.evaluate().isNotEmpty,
          timeout: const Duration(seconds: 30),
          reason: 'the re-auth prompt or the login screen',
        );
        if (reauth.evaluate().isNotEmpty) {
          await typeInto(tester, reauth, password);
          await tapOn(tester, find.byKey(const Key('reauth-continue')));
        }
        await waitFor(tester, login, timeout: const Duration(seconds: 30));
        await waitFor(tester, find.text(l10n.settingsDeleted));
        expect(Supabase.instance.client.auth.currentUser, isNull);
        expect(await Admin.userExists(email), isFalse);
        await shots.both('account_deleted');
      });

      await log.step('signing in with the deleted account fails', () async {
        await signIn();
        final refused = friendlyMessage(const AppFailure.invalidCredentials());
        await waitFor(
          tester,
          find.descendant(
            of: find.byType(AuthMessage),
            matching: find.text(refused),
          ),
          timeout: const Duration(seconds: 20),
        );
        expect(find.byType(NavigationBar), findsNothing);
        await shots.both('deleted_sign_in_refused');
      });

      expect(flutterErrors, isEmpty, reason: flutterErrors.join('\n---\n'));
    } finally {
      for (final line in flutterErrors) {
        debugPrint('E2E_FLUTTER_ERROR $line');
      }
      debugPrint('E2E_SHOTS ${shots.taken.length} ${shots.taken.join(',')}');
      if (shots.failed.isNotEmpty) {
        debugPrint('E2E_SHOTS_FAILED ${shots.failed.join(',')}');
      }
      log.finish();
      friend?.close();
      try {
        await Admin.deleteUser(friendEmail);
        await Admin.deleteUser(email);
      } on Object catch (e) {
        debugPrint('E2E_CLEANUP_FAILED $e');
      }
      FlutterError.onError = testOnError;
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}

String _slug(String label) =>
    label.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');
