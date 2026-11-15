import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/screens/email_verification_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/reset_password_screen.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/dashboard/screens/main_navigation_shell.dart';
import '../../features/expenses/screens/expenses_screen.dart';
import '../../features/insights/screens/insights_screen.dart';
import '../../features/profile/screens/invite_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/startup/not_found_screen.dart';
import '../../features/startup/splash_screen.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pending_invite_provider.dart';
import 'app_routes.dart';
import 'deep_links.dart';

export 'app_routes.dart';

/// How long a page takes to come in.
const Duration pageTransitionDuration = Duration(milliseconds: 280);

CustomTransitionPage<T> _page<T>(GoRouterState state, Widget child) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: pageTransitionDuration,
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

/// Re-runs the redirect when the auth phase or a pending invitation
/// changes.
class _RouterRefresh extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh();
  ref
    ..listen(authControllerProvider.select((s) => s.phase), (_, _) {
      refresh.refresh();
    })
    ..listen(pendingInviteProvider, (_, _) => refresh.refresh());

  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) =>
        platformLinkRedirect(state.uri) ??
        authRedirect(
          phase: ref.read(authControllerProvider).phase,
          location: state.uri,
          pendingInviteToken: ref.read(pendingInviteProvider),
        ),
    errorBuilder: (context, state) => const NotFoundScreen(),
    routes: [
      GoRoute(path: AppRoutes.root, redirect: (_, _) => AppRoutes.dashboard),
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      // Older links: /invite?token=<token>.
      GoRoute(
        path: AppRoutes.invite,
        redirect: (context, state) {
          final token = state.uri.queryParameters['token'];
          return DeepLinks.isValidToken(token)
              ? AppRoutes.inviteFor(token!)
              : AppRoutes.root;
        },
      ),
      GoRoute(
        path: '${AppRoutes.invite}/:token',
        pageBuilder: (context, state) => _page(
          state,
          InviteScreen(token: state.pathParameters['token'] ?? ''),
        ),
      ),
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (context, state) => _page(
          state,
          LoginScreen(initialEmail: state.uri.queryParameters['email']),
        ),
      ),
      GoRoute(
        path: AppRoutes.register,
        pageBuilder: (context, state) => _page(state, const RegisterScreen()),
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        pageBuilder: (context, state) =>
            _page(state, const EmailVerificationScreen()),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        pageBuilder: (context, state) => _page(
          state,
          ForgotPasswordScreen(
            initialEmail: state.uri.queryParameters['email'],
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        pageBuilder: (context, state) =>
            _page(state, const ResetPasswordScreen()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainNavigationShell(navigationShell: navigationShell),
        branches: [
          for (final (path, screen) in const [
            (AppRoutes.dashboard, DashboardScreen()),
            (AppRoutes.expenses, ExpensesScreen()),
            (AppRoutes.insights, InsightsScreen()),
            (AppRoutes.chat, ChatScreen()),
            (AppRoutes.profile, ProfileScreen()),
          ])
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: path,
                  pageBuilder: (context, state) => _page(state, screen),
                ),
              ],
            ),
        ],
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

/// Opens invitation links (cold start included) while the app runs. The
/// token is kept as pending first, so it survives signing in.
final deepLinkHandlerProvider = Provider<void>((ref) {
  final listener = DeepLinkListener(
    source: ref.watch(linkSourceProvider),
    onLink: (link) {
      switch (link) {
        case InviteLink(:final token):
          ref.read(pendingInviteProvider.notifier).set(token);
          ref.read(routerProvider).go(AppRoutes.inviteFor(token));
        case AuthCallbackLink():
          // supabase_flutter exchanges it; the auth events do the rest.
          break;
      }
    },
  );
  ref.onDispose(() => unawaited(listener.dispose()));
});
