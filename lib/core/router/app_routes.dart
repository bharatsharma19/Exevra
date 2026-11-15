/// Route paths, and the pure redirect rules derived from the auth phase.
library;

import '../../providers/auth_provider.dart';

abstract final class AppRoutes {
  static const String root = '/';
  static const String splash = '/splash';
  static const String login = '/login';
  static const String register = '/register';
  static const String verifyEmail = '/verify-email';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  static const String invite = '/invite';
  static const String dashboard = '/dashboard';
  static const String expenses = '/expenses';
  static const String insights = '/insights';
  static const String chat = '/chat';
  static const String profile = '/profile';

  /// Bottom-navigation tabs, in branch order.
  static const List<String> tabs = [
    dashboard,
    expenses,
    insights,
    chat,
    profile,
  ];

  static String inviteFor(String token) =>
      '$invite/${Uri.encodeComponent(token)}';

  /// Screens for signed-out visitors.
  static const Set<String> entryRoutes = {login, register, forgotPassword};

  /// Routes a signed-in user is moved away from.
  static const Set<String> authRoutes = {
    root,
    splash,
    login,
    register,
    forgotPassword,
    verifyEmail,
    resetPassword,
  };

  static bool isInvite(String path) =>
      path == invite || path.startsWith('$invite/');
}

/// [raw] if it is a safe in-app location to return to after signing in:
/// an absolute path (no scheme, host or `//`), not an auth screen.
String? safeReturnTo(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();
  if (!value.startsWith('/') ||
      value.startsWith('//') ||
      value.contains(r'\')) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  if (AppRoutes.authRoutes.contains(uri.path)) return null;
  return value;
}

/// The redirect for [location] in [phase], or null to stay.
///
/// * initializing: only the splash screen (the target is kept in `from`).
/// * signedOut: the entry screens and invitations; anything else goes to
///   the login screen, remembering where the user wanted to go.
/// * needsEmailVerification: only the verification screen.
/// * recoveringPassword: only the set-new-password screen.
/// * signedIn: auth screens lead to a pending invitation, the remembered
///   location or the dashboard.
String? authRedirect({
  required AuthPhase phase,
  required Uri location,
  String? pendingInviteToken,
}) {
  final path = location.path.isEmpty ? AppRoutes.root : location.path;
  final params = location.queryParameters;
  switch (phase) {
    case AuthPhase.initializing:
      if (path == AppRoutes.splash) return null;
      final from = safeReturnTo(location.toString());
      return from == null
          ? AppRoutes.splash
          : '${AppRoutes.splash}?from=${Uri.encodeComponent(from)}';
    case AuthPhase.signedOut:
      if (AppRoutes.entryRoutes.contains(path) || AppRoutes.isInvite(path)) {
        return null;
      }
      final wanted = path == AppRoutes.splash
          ? safeReturnTo(params['from'])
          : safeReturnTo(location.toString());
      if (wanted != null && AppRoutes.isInvite(Uri.parse(wanted).path)) {
        return wanted;
      }
      return wanted == null
          ? AppRoutes.login
          : '${AppRoutes.login}?returnTo=${Uri.encodeComponent(wanted)}';
    case AuthPhase.needsEmailVerification:
      return path == AppRoutes.verifyEmail ? null : AppRoutes.verifyEmail;
    case AuthPhase.recoveringPassword:
      return path == AppRoutes.resetPassword ? null : AppRoutes.resetPassword;
    case AuthPhase.signedIn:
      if (!AppRoutes.authRoutes.contains(path)) return null;
      if (pendingInviteToken != null) {
        return AppRoutes.inviteFor(pendingInviteToken);
      }
      return safeReturnTo(params['returnTo']) ??
          safeReturnTo(params['from']) ??
          AppRoutes.dashboard;
  }
}
