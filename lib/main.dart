import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'core/constants/app_constants.dart';
import 'core/logging/app_logger.dart';
import 'core/router/app_router.dart';
import 'core/router/deep_links.dart';
import 'core/storage/preferences.dart';
import 'core/storage/secure_session_storage.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_locale.dart';
import 'features/auth/screens/app_lock_screen.dart';
import 'features/startup/service_unavailable_app.dart';
import 'models/profile.dart';
import 'providers/app_lock_provider.dart';
import 'providers/profile_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Enforce Portrait Orientation Lock
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 2. Configure Transparent Immersive System Navigation
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

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
  AppLocale.initFromDevice();

  // 4. Initialize the Supabase client (PKCE auth flow) and preferences.
  final SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
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

/// Whether [uri] is the auth email callback that supabase_flutter should
/// exchange for a session.
bool isAuthCallback(Uri uri) =>
    DeepLinks.parse(uri, appLinkHost: AppConfig.environment.appLinkHost)
        is AuthCallbackLink;

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    ref.read(appLockProvider.notifier).onLifecycleChanged(state);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    // Opens invitation links for as long as the app runs.
    ref.watch(deepLinkHandlerProvider);

    final themeMode = switch (ref.watch(themePreferenceProvider)) {
      ThemePreference.light => ThemeMode.light,
      ThemePreference.dark => ThemeMode.dark,
      ThemePreference.system => ThemeMode.system,
    };

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) => LockGate(child: child ?? const SizedBox()),
    );
  }
}

/// Puts the lock screen (or the privacy cover) over the app. While either
/// shows, the app below is kept (so navigation survives) but excluded from
/// semantics, focus, pointer input and animations.
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
        if (lock.showLockScreen)
          const AppLockScreen()
        else if (lock.coverVisible)
          const PrivacyCover(),
      ],
    );
  }
}
