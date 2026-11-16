import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'core/constants/app_constants.dart';
import 'core/logging/app_logger.dart';
import 'core/observability/crash_reporting.dart';
import 'core/router/app_router.dart';
import 'core/router/deep_links.dart';
import 'core/storage/preferences.dart';
import 'core/storage/secure_session_storage.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/system_ui.dart';
import 'core/ui/root_messenger.dart';
import 'core/utils/app_locale.dart';
import 'core/widgets/app_snackbar.dart' show AppSnackbar, SnackbarHost;
import 'features/auth/screens/app_lock_screen.dart';
import 'features/startup/service_unavailable_app.dart';
import 'l10n/l10n.dart';
import 'models/profile.dart';
import 'providers/app_lock_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/profile_provider.dart';

/// Starts the app with crash reporting installed (Sentry only when a
/// `SENTRY_DSN` was compiled in; otherwise errors are logged locally).
Future<void> main() => runAppGuarded(_bootstrap);

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Enforce Portrait Orientation Lock
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 2. The system bars follow the active theme: see ExevraApp's builder
  // (every screen) and the app bar theme (screens with an app bar).

  // 3. Validate the compile-time configuration. An invalid configuration
  // stops here; there is no offline or demo fallback.
  const config = AppConfig.environment;
  final problems = config.problems;
  if (problems.isNotEmpty) {
    AppLogger.error('Invalid build configuration: ${problems.join(' ')}');
    runApp(ServiceUnavailableApp(problems: problems));
    return;
  }

  // Number and date formatting follow the device locale (en_IN fallback).
  await AppLocale.initFromDevice();

  // 4. Initialize the Supabase client (PKCE auth flow) and preferences.
  final SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    await SecureSessionStorage.clearAfterReinstall(prefs);
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        // Tokens and the PKCE verifier live in the keystore.
        localStorage: SecureSessionStorage(
          persistSessionKey: SecureSessionStorage.keyFor(config.supabaseUrl),
        ),
        pkceAsyncStorage: const SecurePkceStorage(),
        // Only the auth callback is an auth link; invitations are handled
        // by the app's own link handler.
        detectSessionInUriPredicate: isAuthCallback,
      ),
    );
  } catch (e, stackTrace) {
    AppLogger.error('Supabase initialization failed', e, stackTrace);
    await captureFailure(e, stackTrace);
    runApp(const ServiceUnavailableApp());
    return;
  }

  // 5. Launch Application with Riverpod State Container
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      // Failed providers surface their error instead of retrying silently.
      retry: (_, _) => null,
      child: const ExevraApp(),
    ),
  );
}

/// Whether [uri] is the PKCE auth callback that supabase_flutter should
/// exchange for a session (never a link that carries tokens).
bool isAuthCallback(Uri uri) => DeepLinks.isSessionCallback(
  uri,
  appLinkHost: AppConfig.environment.appLinkHost,
);

class ExevraApp extends ConsumerStatefulWidget {
  const ExevraApp({super.key});

  @override
  ConsumerState<ExevraApp> createState() => _ExevraAppState();
}

class _ExevraAppState extends ConsumerState<ExevraApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    signInNotice.addListener(_showSignInNotice);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    signInNotice.removeListener(_showSignInNotice);
    _router?.routerDelegate.removeListener(_onRouteChanged);
    _loginShown?.cancel();
    super.dispose();
  }

  GoRouter? _router;
  String? _path;
  Timer? _loginShown;

  /// Whether the login page has come in and the old session's messages
  /// are gone, so a [signInNotice] can show.
  bool _loginReady = false;

  void _watchRoutes(GoRouter router) {
    if (identical(router, _router)) return;
    _router?.routerDelegate.removeListener(_onRouteChanged);
    _router = router;
    router.routerDelegate.addListener(_onRouteChanged);
  }

  /// Signing out clears the snack bars right away (see [build]), but the
  /// main shell stays on screen while the login page comes in, and a
  /// screen of the ended session could still show one meanwhile. They are
  /// cleared again when the login route is entered and once its transition
  /// has finished; a [signInNotice] shows after that.
  void _onRouteChanged() {
    final path = _router?.routerDelegate.currentConfiguration.uri.path;
    final entered = path == AppRoutes.login && _path != AppRoutes.login;
    _path = path;
    if (path != AppRoutes.login) _loginReady = false;
    if (!entered) return;
    clearRootMessages();
    _loginShown?.cancel();
    _loginShown = Timer(pageTransitionDuration, () {
      clearRootMessages();
      _loginReady = true;
      _showSignInNotice();
    });
  }

  void _showSignInNotice() {
    final notice = signInNotice.value;
    if (notice == null || !_loginReady) return;
    signInNotice.value = null;
    AppSnackbar.show(notice.message, kind: notice.kind);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    ref.read(appLockProvider.notifier).onLifecycleChanged(state);
  }

  /// System Back while the lock screen (or the privacy cover) shows never
  /// navigates the app below it. Like Back on the first screen, it moves
  /// the app to the background. This observer is registered before the
  /// router's, so it sees Back first.
  @override
  Future<bool> didPopRoute() async {
    final lock = ref.read(appLockProvider);
    if (!lock.showLockScreen && !lock.coverVisible) return false;
    await SystemNavigator.pop();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    _watchRoutes(router);
    // Opens invitation links for as long as the app runs.
    ref.watch(deepLinkHandlerProvider);

    // Snack bars and banners never outlive the session they belong to
    // (sign-out, account deletion, another user) and never stay up
    // behind the lock screen.
    ref
      ..listen<String?>(currentUserIdProvider, (previous, next) {
        if (previous != next) clearRootMessages();
        // A notice for the sign-in screen is stale once someone signs in.
        if (next != null) signInNotice.value = null;
      })
      ..listen<bool>(appLockProvider.select((lock) => lock.showLockScreen), (
        previous,
        next,
      ) {
        if (next) clearRootMessages();
      });

    final themeMode = switch (ref.watch(themePreferenceProvider)) {
      ThemePreference.light => ThemeMode.light,
      ThemePreference.dark => ThemeMode.dark,
      ThemePreference.system => ThemeMode.system,
    };

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      // The single root messenger: AppSnackbar and every screen's
      // ScaffoldMessenger.of(context) show through it.
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      // SnackbarHost puts snack bars above sheets and dialogs; LockGate
      // stays above everything, snack bars included. SystemUiRegion gives
      // every screen (the lock screen too) status and navigation bar icons
      // that contrast with the resolved theme; app bars and screens that
      // set their own region still override it where they draw.
      builder: (context, child) => SystemUiRegion(
        child: LockGate(child: SnackbarHost(child: child ?? const SizedBox())),
      ),
    );
  }
}

/// Puts the lock screen (or the privacy cover) over the app. While either
/// shows, the app below is kept (so navigation survives) but excluded from
/// semantics, focus, pointer input and animations.
///
/// The cover has a messenger of its own: snack bars of the app (root
/// messenger) are never shown on it, and stay below it.
class LockGate extends ConsumerWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    final hidden = lock.showLockScreen || lock.coverVisible;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: hidden,
          child: ExcludeFocus(
            excluding: hidden,
            child: IgnorePointer(
              ignoring: hidden,
              child: TickerMode(enabled: !hidden, child: child),
            ),
          ),
        ),
        if (hidden)
          ScaffoldMessenger(
            child: lock.showLockScreen
                ? const AppLockScreen()
                : const PrivacyCover(),
          ),
      ],
    );
  }
}
