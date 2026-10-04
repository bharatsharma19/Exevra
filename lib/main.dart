import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/screens/app_lock_screen.dart';
import 'providers/app_lock_provider.dart';
import 'providers/auth_provider.dart';

void main() async {
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

  // 3. Load Environment Configuration (.env with fallback to compile-time defines)
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('[main.dart] Dotenv load notice (using compile-time fallback): $e');
  }

  // 4. Initialize Supabase Backend Client (with resilient fallback for local offline execution)
  final supabaseUrl = (dotenv.isInitialized ? dotenv.env['SUPABASE_URL'] : null) ??
      AppConstants.defaultSupabaseUrl;
  final supabaseKey = (dotenv.isInitialized ? dotenv.env['SUPABASE_ANON_KEY'] : null) ??
      AppConstants.defaultSupabaseAnonKey;

  try {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  } catch (e) {
    debugPrint('[main.dart] Supabase initialization fallback notice: $e');
  }

  // 5. Launch Application with Riverpod State Container
  runApp(
    const ProviderScope(
      child: AntigravityExpenseApp(),
    ),
  );
}

class AntigravityExpenseApp extends ConsumerStatefulWidget {
  const AntigravityExpenseApp({super.key});

  @override
  ConsumerState<AntigravityExpenseApp> createState() => _AntigravityExpenseAppState();
}

class _AntigravityExpenseAppState extends ConsumerState<AntigravityExpenseApp>
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
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      ref.read(appLockProvider.notifier).onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      ref.read(appLockProvider.notifier).onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final authState = ref.watch(authNotifierProvider);
    final appLockState = ref.watch(appLockProvider);

    // Dynamic Theme Mode Selection
    ThemeMode themeMode;
    final activeTheme = authState.profile?.themeMode ?? authState.themeMode;
    switch (activeTheme) {
      case 'light':
        themeMode = ThemeMode.light;
        break;
      case 'dark':
        themeMode = ThemeMode.dark;
        break;
      default:
        themeMode = ThemeMode.system;
    }

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        if (appLockState.isLocked && appLockState.isBiometricsEnabled) {
          return Stack(
            children: [
              if (child != null) child,
              const Positioned.fill(child: AppLockScreen()),
            ],
          );
        }
        return child ?? const SizedBox();
      },
    );
  }
}
