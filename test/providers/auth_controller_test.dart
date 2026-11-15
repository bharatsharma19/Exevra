import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/storage/preferences.dart';
import 'package:expense_manager/data/repositories/account_repository.dart';
import 'package:expense_manager/models/profile.dart';
import 'package:expense_manager/providers/auth_provider.dart';
import 'package:expense_manager/services/auth_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../support/fakes.dart';

class FakeAccountRepository implements AccountRepository {
  AppFailure? failure;
  int calls = 0;
  final List<String?> appleCodes = [];

  @override
  Future<void> deleteAccount({String? appleAuthorizationCode}) async {
    calls++;
    appleCodes.add(appleAuthorizationCode);
    final f = failure;
    if (f != null) throw f;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestBackend backend;
  late FakeAccountRepository accounts;

  Future<ProviderContainer> start({
    String? signedInAs,
    Map<String, Object> prefs = const {},
    bool verified = true,
  }) async {
    backend = TestBackend(signedInAs: signedInAs);
    if (!verified && signedInAs != null) {
      // Replace the initial session with an unconfirmed user.
      backend = TestBackend();
      backend.auth.signInAs(signedInAs, verified: false);
    }
    accounts = FakeAccountRepository();
    final container = await backend.container(
      prefs: prefs,
      extraOverrides: [accountRepositoryProvider.overrideWithValue(accounts)],
    );
    addTearDown(container.dispose);
    container.listen(authControllerProvider, (_, _) {});
    return container;
  }

  AppAuthState stateOf(ProviderContainer c) => c.read(authControllerProvider);
  AuthController controllerOf(ProviderContainer c) =>
      c.read(authControllerProvider.notifier);

  group('initial session', () {
    test('starts initializing until the first event arrives', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final auth = FakeAuthService(emitInitialSession: false);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authServiceProvider.overrideWithValue(auth),
        ],
      );
      addTearDown(container.dispose);
      container.listen(authControllerProvider, (_, _) {});
      await settle();
      expect(
        container.read(authControllerProvider).phase,
        AuthPhase.initializing,
      );
      expect(container.read(currentUserIdProvider), isNull);

      auth.emitInitial();
      await settle();
      expect(container.read(authControllerProvider).phase, AuthPhase.signedOut);
    });

    test('no stored session -> signedOut', () async {
      final c = await start();
      expect(stateOf(c).phase, AuthPhase.signedOut);
      expect(c.read(currentUserIdProvider), isNull);
    });

    test('stored verified session -> signedIn', () async {
      final c = await start(signedInAs: 'A');
      expect(stateOf(c).phase, AuthPhase.signedIn);
      expect(c.read(currentUserIdProvider), 'A');
    });

    test('unconfirmed user -> needsEmailVerification, no user data', () async {
      final c = await start(signedInAs: 'A', verified: false);
      expect(stateOf(c).phase, AuthPhase.needsEmailVerification);
      expect(stateOf(c).verificationEmail, 'a@example.com');
      expect(c.read(currentUserIdProvider), isNull);
    });

    test('an unfinished recovery survives a restart', () async {
      final c = await start(
        signedInAs: 'A',
        prefs: {AuthPrefs.recoveryUser: 'A'},
      );
      expect(stateOf(c).phase, AuthPhase.recoveringPassword);
      expect(c.read(currentUserIdProvider), isNull);
    });

    test('a pending sign-up survives a restart without a session', () async {
      final c = await start(prefs: {AuthPrefs.pendingEmail: 'new@example.com'});
      expect(stateOf(c).phase, AuthPhase.needsEmailVerification);
      expect(stateOf(c).verificationEmail, 'new@example.com');
    });
  });

  group('sign-up', () {
    test('without a session waits for verification', () async {
      final c = await start();
      final failure = await controllerOf(c).signUp(
        email: 'New@Example.com',
        password: 'Passw0rdX',
        displayName: 'New',
      );
      await settle();
      expect(failure, isNull);
      expect(stateOf(c).phase, AuthPhase.needsEmailVerification);
      expect(stateOf(c).verificationEmail, 'new@example.com');
      expect(stateOf(c).user, isNull);
      expect(stateOf(c).resendAvailableAt, isNotNull);
      expect(
        c.read(sharedPreferencesProvider).getString(AuthPrefs.pendingEmail),
        'new@example.com',
      );
    });

    test('a registered address reports account exists', () async {
      final c = await start();
      backend.auth.signUpOutcome = SignUpOutcome.alreadyRegistered;
      final failure = await controllerOf(
        c,
      ).signUp(email: 'a@example.com', password: 'Passw0rdX', displayName: 'A');
      expect(failure, isA<AccountExistsFailure>());
      expect(stateOf(c).phase, AuthPhase.signedOut);
    });

    test('resend is limited to once a minute', () async {
      final c = await start();
      await controllerOf(
        c,
      ).signUp(email: 'n@example.com', password: 'Passw0rdX', displayName: 'N');
      final failure = await controllerOf(c).resendVerification();
      expect(failure, isA<RateLimitedFailure>());
      expect(backend.auth.calls.where((c) => c.startsWith('resend')), isEmpty);
    });

    test('the 6-digit code signs in', () async {
      final c = await start();
      await controllerOf(
        c,
      ).signUp(email: 'n@example.com', password: 'Passw0rdX', displayName: 'N');
      final failure = await controllerOf(c).verifySignupCode('123456');
      await settle();
      expect(failure, isNull);
      expect(stateOf(c).phase, AuthPhase.signedIn);
      expect(stateOf(c).pendingEmail, isNull);
    });

    test('"I have verified" signs in with the remembered password', () async {
      final c = await start();
      backend.auth.confirmedEmails['n@example.com'] = false;
      await controllerOf(
        c,
      ).signUp(email: 'n@example.com', password: 'Passw0rdX', displayName: 'N');
      var (result, failure) = await controllerOf(c).checkVerified();
      expect((result, failure), (VerificationCheck.notYet, null));

      backend.auth.confirmedEmails['n@example.com'] = true;
      (result, failure) = await controllerOf(c).checkVerified();
      await settle();
      expect(result, VerificationCheck.verified);
      expect(stateOf(c).phase, AuthPhase.signedIn);
    });

    test('without a remembered password it asks for one', () async {
      final c = await start(prefs: {AuthPrefs.pendingEmail: 'n@example.com'});
      final (result, _) = await controllerOf(c).checkVerified();
      expect(result, VerificationCheck.needsPassword);
    });

    test('a session re-check picks up the confirmation', () async {
      final c = await start(signedInAs: 'A', verified: false);
      backend.auth.reloadedUser = fakeUser('A');
      final (result, _) = await controllerOf(c).checkVerified();
      expect(result, VerificationCheck.verified);
      expect(stateOf(c).phase, AuthPhase.signedIn);
    });
  });

  group('sign-in', () {
    test('an unconfirmed address moves to verification', () async {
      final c = await start();
      backend.auth.confirmedEmails['u@example.com'] = false;
      final failure = await controllerOf(c).signIn('u@example.com', 'weak');
      expect(failure, isNull);
      expect(stateOf(c).phase, AuthPhase.needsEmailVerification);
      expect(stateOf(c).verificationEmail, 'u@example.com');
    });

    test('wrong credentials stay signed out with a typed failure', () async {
      final c = await start();
      backend.auth.failNext = const AppFailure.invalidCredentials();
      final failure = await controllerOf(c).signIn('u@example.com', 'x');
      expect(failure, isA<InvalidCredentialsFailure>());
      expect(stateOf(c).phase, AuthPhase.signedOut);
      expect(stateOf(c).isLoading, isFalse);
    });

    test('cancelling Google is silent', () async {
      final c = await start();
      backend.auth.googleUserId = null;
      expect(await controllerOf(c).signInWithGoogle(), isNull);
      expect(stateOf(c).phase, AuthPhase.signedOut);
    });

    test('Google sign-in follows the signedIn event', () async {
      final c = await start();
      backend.auth.googleUserId = 'G';
      expect(await controllerOf(c).signInWithGoogle(), isNull);
      await settle();
      expect(c.read(currentUserIdProvider), 'G');
    });

    test('cancelling Apple is silent', () async {
      final c = await start();
      expect(await controllerOf(c).signInWithApple(), isNull);
      expect(stateOf(c).phase, AuthPhase.signedOut);
    });

    test('Apple keeps the shared name when the profile has none', () async {
      final c = await start();
      backend.profiles.profiles['ap'] = profileOf(
        'ap',
      ).copyWith(displayName: 'ap');
      backend.auth.appleResult = () => AppleSignInResult(
        user: fakeUser('ap'),
        name: const AppleName(givenName: 'Ada', familyName: 'Lovelace'),
      );
      expect(await controllerOf(c).signInWithApple(), isNull);
      await settle();
      expect(backend.auth.calls, contains('fullName:Ada Lovelace'));
      expect(backend.profiles.profiles['ap']!.displayName, 'Ada Lovelace');
    });

    test('Apple never overwrites a name the user chose', () async {
      final c = await start();
      backend.profiles.profiles['ap'] = profileOf('ap');
      backend.auth.appleResult = () => AppleSignInResult(
        user: fakeUser('ap'),
        name: const AppleName(givenName: 'Ada'),
      );
      await controllerOf(c).signInWithApple();
      await settle();
      expect(backend.profiles.profiles['ap']!.displayName, 'User ap');
      expect(backend.profiles.updates, isEmpty);
    });
  });

  group('password recovery', () {
    test('the link event forces a new password before anything else', () async {
      final c = await start();
      backend.auth.emit(
        supabase.AuthChangeEvent.passwordRecovery,
        fakeUser('A'),
      );
      await settle();
      expect(stateOf(c).phase, AuthPhase.recoveringPassword);
      expect(c.read(currentUserIdProvider), isNull);

      // A token refresh keeps the recovery.
      backend.auth.emit(supabase.AuthChangeEvent.tokenRefreshed, fakeUser('A'));
      await settle();
      expect(stateOf(c).phase, AuthPhase.recoveringPassword);
    });

    test('code + new password ends signed in, late events ignored', () async {
      final c = await start();
      final failure = await controllerOf(c).resetPasswordWithCode(
        email: 'a@example.com',
        code: '123456',
        newPassword: 'NewPassw0rd',
      );
      await settle();
      expect(failure, isNull);
      expect(stateOf(c).phase, AuthPhase.signedIn);
      expect(backend.auth.calls, contains('updatePassword'));
      expect(
        c.read(sharedPreferencesProvider).getString(AuthPrefs.recoveryUser),
        isNull,
      );
    });

    test('a failed password update keeps the recovery screen', () async {
      final c = await start();
      backend.auth.failPasswordUpdate = const AppFailure.weakPassword();
      final failure = await controllerOf(c).resetPasswordWithCode(
        email: 'a@example.com',
        code: '123456',
        newPassword: 'weak',
      );
      await settle();
      expect(failure, isA<WeakPasswordFailure>());
      expect(stateOf(c).phase, AuthPhase.recoveringPassword);

      expect(await controllerOf(c).setNewPassword('NewPassw0rd'), isNull);
      await settle();
      expect(stateOf(c).phase, AuthPhase.signedIn);
    });

    test('a wrong code stays where it was', () async {
      final c = await start();
      backend.auth.failNext = const AppFailure.codeExpired();
      final failure = await controllerOf(c).resetPasswordWithCode(
        email: 'a@example.com',
        code: '000000',
        newPassword: 'NewPassw0rd',
      );
      expect(failure, isA<CodeExpiredFailure>());
      expect(stateOf(c).phase, AuthPhase.signedOut);
    });

    test('cancelling signs out', () async {
      final c = await start();
      backend.auth.emit(
        supabase.AuthChangeEvent.passwordRecovery,
        fakeUser('A'),
      );
      await settle();
      await controllerOf(c).cancelRecovery();
      await settle();
      expect(stateOf(c).phase, AuthPhase.signedOut);
    });
  });

  group('sign-out', () {
    test('a late token refresh does not sign the user back in', () async {
      final c = await start(signedInAs: 'A');
      await controllerOf(c).signOut();
      backend.auth.emit(supabase.AuthChangeEvent.tokenRefreshed, fakeUser('A'));
      backend.auth.emit(supabase.AuthChangeEvent.userUpdated, fakeUser('A'));
      await settle();
      expect(stateOf(c).phase, AuthPhase.signedOut);
      expect(c.read(currentUserIdProvider), isNull);
    });

    test('userDeleted ends the session', () async {
      final c = await start(signedInAs: 'A');
      // ignore: deprecated_member_use
      backend.auth.emit(supabase.AuthChangeEvent.userDeleted);
      await settle();
      expect(stateOf(c).phase, AuthPhase.signedOut);
    });

    test("clears the user's device preferences but keeps the theme", () async {
      final c = await start(
        signedInAs: 'A',
        prefs: {
          UserPrefs.key('A', UserPrefs.haptics): false,
          UserPrefs.key('A', UserPrefs.appLock): true,
          'app_theme_mode': ThemePreference.dark.name,
        },
      );
      await controllerOf(c).signOut();
      await settle();
      final prefs = c.read(sharedPreferencesProvider);
      expect(prefs.getBool(UserPrefs.key('A', UserPrefs.haptics)), isNull);
      // App Lock stays on for the account's next sign-in on this device.
      expect(prefs.getBool(UserPrefs.key('A', UserPrefs.appLock)), isTrue);
      expect(prefs.getString('app_theme_mode'), 'dark');
      expect(backend.auth.signOutCalls, 1);
    });
  });

  group('account deletion', () {
    test('a failure keeps the session and the data', () async {
      final c = await start(
        signedInAs: 'A',
        prefs: {UserPrefs.key('A', UserPrefs.appLock): true},
      );
      accounts.failure = const AppFailure.business('deletion_failed');
      final failure = await controllerOf(c).deleteAccount();
      await settle();
      expect(failure, isA<BusinessFailure>());
      expect(stateOf(c).phase, AuthPhase.signedIn);
      expect(stateOf(c).isLoading, isFalse);
      expect(backend.auth.signOutCalls, 0);
      expect(
        c
            .read(sharedPreferencesProvider)
            .getBool(UserPrefs.key('A', UserPrefs.appLock)),
        isTrue,
      );
    });

    test('an Apple user\'s fresh authorization code is sent', () async {
      final c = await start(signedInAs: 'A');
      backend.auth.appleCode = 'apple-code';
      expect(await controllerOf(c).deleteAccount(), isNull);
      expect(accounts.appleCodes, ['apple-code']);
    });

    test('cancelling the Apple confirmation deletes nothing', () async {
      final c = await start(signedInAs: 'A');
      backend.auth.appleCodeFailure = const AppFailure.business(
        'apple_reauth_cancelled',
      );
      final failure = await controllerOf(c).deleteAccount();
      await settle();
      expect(failure, const AppFailure.business('apple_reauth_cancelled'));
      expect(accounts.calls, 0);
      expect(stateOf(c).phase, AuthPhase.signedIn);
      expect(stateOf(c).isLoading, isFalse);
    });

    test('success signs out and clears the device data', () async {
      final c = await start(
        signedInAs: 'A',
        prefs: {UserPrefs.key('A', UserPrefs.appLock): true},
      );
      expect(await controllerOf(c).deleteAccount(), isNull);
      await settle();
      expect(accounts.calls, 1);
      expect(stateOf(c).phase, AuthPhase.signedOut);
      expect(backend.auth.signOutCalls, 1);
      expect(
        c
            .read(sharedPreferencesProvider)
            .getBool(UserPrefs.key('A', UserPrefs.appLock)),
        isNull,
      );
    });
  });
}
