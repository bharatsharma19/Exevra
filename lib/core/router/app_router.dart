import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/phone_otp_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/reset_password_screen.dart';
import '../../features/auth/screens/email_verification_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/dashboard/screens/main_navigation_shell.dart';
import '../../features/expenses/screens/expenses_screen.dart';
import '../../features/insights/screens/insights_screen.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/profile/screens/invite_screen.dart';
import '../../features/profile/screens/profile_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _dashboardNavigatorKey =
    GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _expensesNavigatorKey =
    GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _insightsNavigatorKey =
    GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _chatNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _profileNavigatorKey =
    GlobalKey<NavigatorState>();

CustomTransitionPage<T> _buildAnimatedPage<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubicEmphasized,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.02, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class RouterNotifier extends ChangeNotifier {
  final Ref _ref;
  RouterNotifier(this._ref) {
    _ref.listen<AppAuthState>(authNotifierProvider, (previous, next) {
      if (previous?.status != next.status ||
          previous?.isEmailVerified != next.isEmailVerified ||
          previous?.user?.emailConfirmedAt != next.user?.emailConfirmedAt) {
        notifyListeners();
      }
    });
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final routerNotifier = RouterNotifier(ref);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/dashboard',
    refreshListenable: routerNotifier,
    redirect: (context, state) {
      final authState = ref.read(authNotifierProvider);
      final isAuth = authState.isAuthenticated;
      final isVerified = authState.isEmailVerified;
      final loc = state.matchedLocation;

      final isAuthRoute =
          loc == '/login' ||
          loc == '/register' ||
          loc == '/phone-auth' ||
          loc == '/forgot-password' ||
          loc == '/reset-password';

      // Routes that an already authenticated & verified user should NOT stay on
      final isAuthScreenToExit =
          loc == '/login' ||
          loc == '/register' ||
          loc == '/phone-auth' ||
          loc == '/forgot-password';

      final isInviteRoute = loc.startsWith('/invite');

      bool isValidReturnTo(String? path) {
        if (path == null || path.trim().isEmpty) return false;
        final trimmed = path.trim();
        // Prevent open redirect to external domains: must start with / and not //
        return trimmed.startsWith('/') &&
            !trimmed.startsWith('//') &&
            !trimmed.contains('\\');
      }

      final rawReturnTo = state.uri.queryParameters['returnTo'];
      final safeReturnTo = isValidReturnTo(rawReturnTo) ? rawReturnTo! : null;

      // 1. Not authenticated: send to /login unless already on an auth route or invite route
      if (!isAuth && !isAuthRoute && !isInviteRoute) {
        return '/login';
      }

      // 2. Authenticated but unverified: redirect to /verify-email (except invite route to allow viewing)
      if (isAuth && !isVerified) {
        if (loc != '/verify-email' && !isInviteRoute && loc != '/reset-password') {
          if (safeReturnTo != null) {
            return '/verify-email?returnTo=${Uri.encodeComponent(safeReturnTo)}';
          }
          return '/verify-email';
        }
        return null;
      }

      // 3. Authenticated & verified: exit auth entry screens
      // NOTE: /reset-password is purposefully excluded so users recovering passwords can submit new password!
      if (isAuth && isVerified && (isAuthScreenToExit || loc == '/verify-email')) {
        if (safeReturnTo != null) {
          return safeReturnTo;
        }
        return '/dashboard';
      }

      return null;
    },
    routes: [
      // -----------------------------------------------------------------------
      // AUTHENTICATION & VERIFICATION ROUTES
      // -----------------------------------------------------------------------
      GoRoute(
        path: '/invite',
        builder: (context, state) {
          final token = state.uri.queryParameters['token'] ?? '';
          return InviteScreen(token: token);
        },
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _buildAnimatedPage(
          context: context,
          state: state,
          child: const LoginScreen(),
        ),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (context, state) => _buildAnimatedPage(
          context: context,
          state: state,
          child: const RegisterScreen(),
        ),
      ),
      GoRoute(
        path: '/verify-email',
        pageBuilder: (context, state) => _buildAnimatedPage(
          context: context,
          state: state,
          child: const EmailVerificationScreen(),
        ),
      ),
      GoRoute(
        path: '/phone-auth',
        pageBuilder: (context, state) => _buildAnimatedPage(
          context: context,
          state: state,
          child: const PhoneOtpScreen(),
        ),
      ),
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (context, state) => _buildAnimatedPage(
          context: context,
          state: state,
          child: const ForgotPasswordScreen(),
        ),
      ),
      GoRoute(
        path: '/reset-password',
        pageBuilder: (context, state) => _buildAnimatedPage(
          context: context,
          state: state,
          child: const ResetPasswordScreen(),
        ),
      ),

      // -----------------------------------------------------------------------
      // MAIN STATEFUL NAVIGATION SHELL
      // -----------------------------------------------------------------------
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainNavigationShell(navigationShell: navigationShell);
        },
        branches: [
          // Branch 0: Dashboard
          StatefulShellBranch(
            navigatorKey: _dashboardNavigatorKey,
            routes: [
              GoRoute(
                path: '/dashboard',
                pageBuilder: (context, state) => _buildAnimatedPage(
                  context: context,
                  state: state,
                  child: const DashboardScreen(),
                ),
              ),
            ],
          ),

          // Branch 1: Expenses
          StatefulShellBranch(
            navigatorKey: _expensesNavigatorKey,
            routes: [
              GoRoute(
                path: '/expenses',
                pageBuilder: (context, state) => _buildAnimatedPage(
                  context: context,
                  state: state,
                  child: const ExpensesScreen(),
                ),
              ),
            ],
          ),

          // Branch 2: Insights
          StatefulShellBranch(
            navigatorKey: _insightsNavigatorKey,
            routes: [
              GoRoute(
                path: '/insights',
                pageBuilder: (context, state) => _buildAnimatedPage(
                  context: context,
                  state: state,
                  child: const InsightsScreen(),
                ),
              ),
            ],
          ),

          // Branch 3: Chat Assistant
          StatefulShellBranch(
            navigatorKey: _chatNavigatorKey,
            routes: [
              GoRoute(
                path: '/chat',
                pageBuilder: (context, state) => _buildAnimatedPage(
                  context: context,
                  state: state,
                  child: const ChatScreen(),
                ),
              ),
            ],
          ),

          // Branch 4: Profile & Settings
          StatefulShellBranch(
            navigatorKey: _profileNavigatorKey,
            routes: [
              GoRoute(
                path: '/profile',
                pageBuilder: (context, state) => _buildAnimatedPage(
                  context: context,
                  state: state,
                  child: const ProfileScreen(),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
