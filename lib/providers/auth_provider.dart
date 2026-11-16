import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../core/errors/app_failure.dart';
import '../core/logging/app_logger.dart';
import '../core/storage/preferences.dart';
import '../core/utils/haptics.dart';
import '../data/repositories/account_repository.dart';
import '../data/repositories/profile_repository.dart';
import '../models/profile.dart';
import '../services/auth_service.dart';
import 'profile_provider.dart';
import '../core/utils/app_clock.dart';

export '../services/auth_service.dart' show authServiceProvider;

/// Where the user is in the sign-in life cycle. The router derives every
/// redirect from this.
enum AuthPhase {
  /// Waiting for the stored session to be restored. Nothing is shown but
  /// the splash screen.
  initializing,

  signedOut,

  /// Signed up (or signed in) with an address that is not confirmed yet.
  /// There may be no session at all.
  needsEmailVerification,

  /// Holding a recovery session: the only thing allowed is setting a new
  /// password (or signing out).
  recoveringPassword,

  signedIn,
}

/// Result of "I've verified my email".
enum VerificationCheck { verified, notYet, needsPassword }

@immutable
class AppAuthState {
  const AppAuthState({
    this.phase = AuthPhase.initializing,
    this.user,
    this.pendingEmail,
    this.isLoading = false,
    this.resendAvailableAt,
    this.signedInHere = false,
  });

  final AuthPhase phase;

  /// The session's user (null when there is no session).
  final supabase.User? user;

  /// The address waiting for confirmation (also without a session).
  final String? pendingEmail;

  /// An auth action is running.
  final bool isLoading;

  /// When the confirmation email may be sent again.
  final DateTime? resendAvailableAt;

  /// The user signed in to the account in this app run (a sign-in, a
  /// confirmed sign-up or a password reset), rather than the stored
  /// session being restored at start-up.
  final bool signedInHere;

  bool get isSignedIn => phase == AuthPhase.signedIn && user != null;

  /// The address shown on the verification screen.
  String? get verificationEmail => pendingEmail ?? user?.email;

  AppAuthState _copy({
    AuthPhase? phase,
    supabase.User? Function()? user,
    String? Function()? pendingEmail,
    bool? isLoading,
    DateTime? Function()? resendAvailableAt,
    bool? signedInHere,
  }) => AppAuthState(
    phase: phase ?? this.phase,
    user: user == null ? this.user : user(),
    pendingEmail: pendingEmail == null ? this.pendingEmail : pendingEmail(),
    isLoading: isLoading ?? this.isLoading,
    resendAvailableAt: resendAvailableAt == null
        ? this.resendAvailableAt
        : resendAvailableAt(),
    signedInHere: signedInHere ?? this.signedInHere,
  );
}

bool _isConfirmed(supabase.User user) {
  final confirmed = user.emailConfirmedAt;
  return confirmed != null && confirmed.isNotEmpty;
}

/// Device keys the controller keeps across restarts (no user data).
abstract final class AuthPrefs {
  /// The address of a sign-up waiting for confirmation.
  static const String pendingEmail = 'auth.pending_email';

  /// The user id holding a recovery session that has not set a new
  /// password yet. Survives a restart so the app cannot be entered
  /// without one.
  static const String recoveryUser = 'auth.recovery_user';
}

/// The single writer of the auth state.
///
/// Who is signed in comes only from Supabase's auth events. Actions add
/// what the events cannot know: an unconfirmed sign-up without a session,
/// and the end of a password recovery. Every action returns its failure
/// (or null) so the calling screen shows it once.
class AuthController extends Notifier<AppAuthState> {
  AuthService get _service => ref.read(authServiceProvider);

  supabase.User? _user;
  bool _signedInHere = false;
  String? _pendingEmail;
  String? _recoveryUserId;
  bool _initialised = false;
  Timer? _initTimer;

  /// The access token of a recovery this app already completed; a late
  /// `passwordRecovery` event for it must not reopen the recovery.
  final Set<String> _completedRecoveryTokens = {};

  /// Accounts deleted in this app run; their App Lock flag goes with the
  /// rest of their device data.
  final Set<String> _deletedAccounts = {};

  /// Password typed at sign-up or sign-in, kept in memory only, so
  /// "I've verified" can sign in without asking again.
  String? _rememberedPassword;

  static const Duration resendCooldown = Duration(seconds: 60);
  static const Duration initialSessionTimeout = Duration(seconds: 6);

  @override
  AppAuthState build() {
    final service = ref.watch(authServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    _pendingEmail = prefs.getString(AuthPrefs.pendingEmail);
    _recoveryUserId = prefs.getString(AuthPrefs.recoveryUser);

    final sub = service.authStateChanges.listen(
      _onAuthEvent,
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.warn('Auth stream error', ErrorMapper.map(error, stackTrace));
      },
    );
    // If the initial event never arrives, fall back to the restored
    // session instead of showing the splash screen forever.
    _initTimer = Timer(initialSessionTimeout, () {
      if (!_initialised) {
        _settle(service.currentSession?.user, restored: true);
      }
    });
    ref.onDispose(() {
      _initTimer?.cancel();
      unawaited(sub.cancel());
    });

    // When a user leaves (sign-out, deletion, switch), wipe their device
    // data. The theme is device-wide and stays.
    listenSelf((previous, next) {
      final left = previous?.user?.id;
      if (left != null && left != next.user?.id) {
        unawaited(_clearUserData(left));
      }
    });

    return const AppAuthState();
  }

  // ---------------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------------

  void _onAuthEvent(supabase.AuthState data) {
    if (!ref.mounted) return;
    final user = data.session?.user;
    switch (data.event) {
      case supabase.AuthChangeEvent.initialSession:
        _settle(user, restored: true);
      case supabase.AuthChangeEvent.signedIn:
        _settle(user);
      case supabase.AuthChangeEvent.passwordRecovery:
        final token = data.session?.accessToken;
        if (user == null || _completedRecoveryTokens.contains(token)) return;
        _setRecoveryUser(user.id);
        _settle(user);
      case supabase.AuthChangeEvent.signedOut:
        _rememberedPassword = null;
        _setRecoveryUser(null);
        _settle(null);
      // userDeleted is deprecated in gotrue and not sent today; if a server
      // sends it, it ends the session like a sign-out.
      // ignore: deprecated_member_use
      case supabase.AuthChangeEvent.userDeleted:
        _rememberedPassword = null;
        _setPendingEmail(null);
        _setRecoveryUser(null);
        _settle(null);
      case supabase.AuthChangeEvent.tokenRefreshed ||
          supabase.AuthChangeEvent.userUpdated ||
          supabase.AuthChangeEvent.mfaChallengeVerified:
        // Only refreshes the current user. After a local sign-out a late
        // refresh must not bring the session back.
        final current = _user;
        if (current == null || user == null || user.id != current.id) return;
        if (_service.currentSession == null) return;
        _settle(user);
    }
  }

  /// Recomputes the phase for [user] and publishes it. [restored] marks
  /// the session restored at start-up; any other new user signed in here.
  void _settle(supabase.User? user, {bool restored = false}) {
    _initialised = true;
    _initTimer?.cancel();
    final sameUser = user != null && user.id == _user?.id;
    _signedInHere = user != null && (sameUser ? _signedInHere : !restored);
    _user = user;
    if (user != null) {
      if (_isConfirmed(user)) {
        _setPendingEmail(null);
        _rememberedPassword = null;
      } else if (user.email != null) {
        _setPendingEmail(user.email);
      }
      if (_recoveryUserId != null && _recoveryUserId != user.id) {
        _setRecoveryUser(null);
      }
    }
    state = state._copy(
      phase: _phaseFor(user),
      user: () => user,
      pendingEmail: () => _pendingEmail,
      signedInHere: _signedInHere,
    );
  }

  AuthPhase _phaseFor(supabase.User? user) {
    if (user == null) {
      return _pendingEmail != null
          ? AuthPhase.needsEmailVerification
          : AuthPhase.signedOut;
    }
    if (_recoveryUserId == user.id) return AuthPhase.recoveringPassword;
    if (!_isConfirmed(user)) return AuthPhase.needsEmailVerification;
    return AuthPhase.signedIn;
  }

  void _setPendingEmail(String? email) {
    final normalised = email?.trim().toLowerCase();
    if (_pendingEmail == normalised) return;
    _pendingEmail = normalised;
    _writePref(AuthPrefs.pendingEmail, normalised);
  }

  void _setRecoveryUser(String? userId) {
    if (_recoveryUserId == userId) return;
    _recoveryUserId = userId;
    _writePref(AuthPrefs.recoveryUser, userId);
  }

  void _writePref(String key, String? value) {
    final prefs = ref.read(sharedPreferencesProvider);
    unawaited(
      (value == null ? prefs.remove(key) : prefs.setString(key, value))
          .then<void>((_) {})
          .catchError((Object e) {
            AppLogger.warn('Could not save auth state', e.runtimeType);
          }),
    );
  }

  Future<void> _clearUserData(String userId) async {
    AppHaptics.isEnabled = true;
    // A plain sign-out keeps the App Lock flag, so signing straight back
    // in (one tap with Google) cannot skip the lock.
    final deleted = _deletedAccounts.remove(userId);
    try {
      await UserPrefs.clearUser(
        ref.read(sharedPreferencesProvider),
        userId,
        keepAppLock: !deleted,
      );
    } on Object catch (e) {
      AppLogger.warn('Could not clear user preferences', e.runtimeType);
    }
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Runs [action] with the loading flag. Returns the failure, or null.
  Future<AppFailure?> _run(Future<void> Function() action) async {
    state = state._copy(isLoading: true);
    try {
      await action();
      AppHaptics.success();
      return null;
    } catch (error, stackTrace) {
      AppHaptics.error();
      return ErrorMapper.map(error, stackTrace);
    } finally {
      if (ref.mounted) state = state._copy(isLoading: false);
    }
  }

  /// Signs in with email and password. An unconfirmed address moves to
  /// the verification screen instead of failing.
  Future<AppFailure?> signIn(String email, String password) async {
    final failure = await _run(
      () => _service.signIn(email: email, password: password),
    );
    if (failure is EmailNotConfirmedFailure && ref.mounted) {
      _rememberedPassword = password;
      _setPendingEmail(email);
      _settle(_user);
      return null;
    }
    return failure;
  }

  /// Creates an account. A duplicate address returns
  /// [AccountExistsFailure] (the screen offers sign-in and reset).
  Future<AppFailure?> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    SignUpOutcome? outcome;
    final failure = await _run(() async {
      outcome = await _service.signUp(
        email: email,
        password: password,
        displayName: displayName,
      );
    });
    if (failure != null || !ref.mounted) return failure;
    switch (outcome) {
      case SignUpOutcome.alreadyRegistered:
        return const AppFailure.accountExists();
      case SignUpOutcome.confirmationSent:
        _rememberedPassword = password;
        _setPendingEmail(email);
        state = state._copy(
          resendAvailableAt: () => AppClock.now().add(resendCooldown),
        );
        _settle(_user);
      case SignUpOutcome.signedIn || null:
        break; // The signedIn event moves on.
    }
    return null;
  }

  /// Sends the confirmation email again (60 s apart).
  Future<AppFailure?> resendVerification() async {
    final email = state.verificationEmail;
    if (email == null) return const AppFailure.sessionExpired();
    final availableAt = state.resendAvailableAt;
    if (availableAt != null && AppClock.now().isBefore(availableAt)) {
      return const AppFailure.rateLimited();
    }
    final failure = await _run(() => _service.resendSignupConfirmation(email));
    if (ref.mounted && (failure == null || failure is RateLimitedFailure)) {
      state = state._copy(
        resendAvailableAt: () => AppClock.now().add(resendCooldown),
      );
    }
    return failure;
  }

  /// Confirms the address with the 8-digit code (works on any device).
  Future<AppFailure?> verifySignupCode(String code) async {
    final email = state.verificationEmail;
    if (email == null) return const AppFailure.sessionExpired();
    return _run(() => _service.verifySignupCode(email: email, code: code));
  }

  /// Checks whether the address was confirmed (for example through the
  /// link on another device). Without a session it signs in with the
  /// password typed earlier, or with [password].
  Future<(VerificationCheck, AppFailure?)> checkVerified({
    String? password,
  }) async {
    final email = state.verificationEmail;
    if (email == null) return (VerificationCheck.notYet, null);
    if (_user != null) {
      supabase.User? fresh;
      final failure = await _run(() async {
        fresh = await _service.reloadUser();
      });
      if (failure != null) return (VerificationCheck.notYet, failure);
      final user = fresh;
      if (user != null && ref.mounted && _user?.id == user.id) _settle(user);
      return (
        user != null && _isConfirmed(user)
            ? VerificationCheck.verified
            : VerificationCheck.notYet,
        null,
      );
    }
    final secret = password ?? _rememberedPassword;
    if (secret == null) return (VerificationCheck.needsPassword, null);
    final failure = await _run(
      () => _service.signIn(email: email, password: secret),
    );
    if (failure is EmailNotConfirmedFailure) {
      _rememberedPassword = secret;
      return (VerificationCheck.notYet, null);
    }
    if (failure != null) return (VerificationCheck.notYet, failure);
    // The signedIn event finishes the move to the app.
    return (VerificationCheck.verified, null);
  }

  /// Leaves the verification step (wrong address, other account).
  Future<void> cancelVerification() async {
    _rememberedPassword = null;
    _setPendingEmail(null);
    if (_user != null) {
      await signOut();
    } else {
      _settle(null);
    }
  }

  /// Emails an 8-digit password reset code.
  Future<AppFailure?> sendPasswordResetCode(String email) =>
      _run(() => _service.sendPasswordResetCode(email));

  /// Exchanges the reset code for a recovery session and sets the new
  /// password. If the password step fails, the recovery screen takes over.
  Future<AppFailure?> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    String? token;
    final verifyFailure = await _run(() async {
      token = await _service.verifyRecoveryCode(email: email, code: code);
    });
    if (verifyFailure != null || !ref.mounted) return verifyFailure;
    final user = _service.currentUser;
    if (user != null) {
      _setRecoveryUser(user.id);
      _settle(user);
    }
    return _completeRecovery(newPassword, token);
  }

  /// Sets the new password for the current recovery session.
  Future<AppFailure?> setNewPassword(String newPassword) =>
      _completeRecovery(newPassword, _service.currentSession?.accessToken);

  Future<AppFailure?> _completeRecovery(String password, String? token) async {
    final failure = await _run(() => _service.updatePassword(password));
    if (failure != null || !ref.mounted) return failure;
    if (token != null) _completedRecoveryTokens.add(token);
    _setRecoveryUser(null);
    _settle(_service.currentUser ?? _user);
    return null;
  }

  /// Abandons a recovery: the recovery session ends.
  Future<void> cancelRecovery() => signOut();

  /// Cancelling the Google account picker is not a failure.
  Future<AppFailure?> signInWithGoogle() => _run(() async {
    await _service.signInWithGoogle();
  });

  Future<AppFailure?> signInWithApple() async {
    AppleSignInResult? result;
    final failure = await _run(() async {
      result = await _service.signInWithApple();
    });
    final signedIn = result;
    if (failure == null && signedIn != null) {
      unawaited(_keepAppleName(signedIn));
    }
    return failure;
  }

  /// Apple shares the name only on the first authorisation: store it as
  /// the display name while the profile still has the generated one.
  Future<void> _keepAppleName(AppleSignInResult result) async {
    final user = result.user;
    final name = result.name.fullName;
    if (user == null || name == null) return;
    try {
      await _service.updateFullName(name);
      final repo = ref.read(profileRepositoryProvider);
      final profile = await repo.fetch(user.id);
      final generated = {'', 'User', (user.email ?? '').split('@').first};
      if (!generated.contains(profile.displayName.trim())) return;
      await repo.update(user.id, ProfileUpdate(displayName: name));
      if (ref.mounted) ref.invalidate(profileProvider);
    } on Object catch (e) {
      AppLogger.warn('Apple name was not saved', e.runtimeType);
    }
  }

  /// Signs out on this device. The local state is cleared first, so a
  /// slow or failed server call never keeps the user signed in.
  Future<void> signOut() async {
    _rememberedPassword = null;
    _appleCodeForDeletion = null;
    _setPendingEmail(null);
    _setRecoveryUser(null);
    _settle(null);
    await _service.signOut();
  }

  /// How the user signs in again when the server asks for a recent sign-in
  /// (`reauth_required`), or null when the app cannot offer it.
  ReauthMethod? get reauthMethod => _service.reauthMethod;

  /// Signs the user in again as the same account (see
  /// [AuthService.reauthenticate]). Returns the failure, or null.
  Future<AppFailure?> reauthenticate({String? password}) async {
    state = state._copy(isLoading: true);
    try {
      _appleCodeForDeletion = await _service.reauthenticate(password: password);
      return null;
    } catch (error, stackTrace) {
      return ErrorMapper.map(error, stackTrace);
    } finally {
      if (ref.mounted) state = state._copy(isLoading: false);
    }
  }

  /// The Apple code from [reauthenticate], used by the next deletion so
  /// the user is not asked by Apple twice.
  String? _appleCodeForDeletion;

  /// Deletes the account on the server, then signs out. On failure the
  /// session and all local data are kept and the failure is returned.
  ///
  /// The server wants a recent sign-in: when the session is older it
  /// answers `reauth_required`; call [reauthenticate] and then this again.
  /// Users who signed in with Apple confirm with Apple first, so the
  /// server can revoke the app's Apple token along with the account.
  Future<AppFailure?> deleteAccount() async {
    state = state._copy(isLoading: true);
    try {
      final reused = _appleCodeForDeletion;
      _appleCodeForDeletion = null;
      final appleCode = reused ?? await _service.appleAuthorizationCode();
      await ref
          .read(accountRepositoryProvider)
          .deleteAccount(appleAuthorizationCode: appleCode);
    } on AppFailure catch (failure) {
      return failure;
    } finally {
      if (ref.mounted) state = state._copy(isLoading: false);
    }
    final deleted = state.user?.id;
    if (deleted != null) _deletedAccounts.add(deleted);
    await signOut();
    return null;
  }
}

final authControllerProvider = NotifierProvider<AuthController, AppAuthState>(
  AuthController.new,
);

/// The signed-in, verified user's id, or null (also while recovering a
/// password). Every user-scoped provider watches this, so a sign-out or
/// user switch rebuilds them with no data from the previous user.
final currentUserIdProvider = Provider<String?>((ref) {
  final auth = ref.watch(authControllerProvider);
  return auth.isSignedIn ? auth.user!.id : null;
});
