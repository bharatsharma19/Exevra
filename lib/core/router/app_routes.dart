/// Route paths, and the pure redirect rules derived from the auth phase.
library;

import '../../providers/auth_provider.dart';
import '../config/app_config.dart';
import 'deep_links.dart';

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
  static const String onboarding = '/onboarding';

  /// About for signed-out visitors (no Delete account).
  static const String about = '/about';

  /// About for a signed-in user, inside the profile tab.
  static const String profileAbout = '$profile/about';

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
  static const Set<String> entryRoutes = {
    login,
    register,
    forgotPassword,
    about,
  };

  /// Routes a signed-in user is moved away from.
  static const Set<String> authRoutes = {
    root,
    splash,
    login,
    register,
    forgotPassword,
    verifyEmail,
    resetPassword,
    onboarding,
  };

  static bool isInvite(String path) =>
      path == invite || path.startsWith('$invite/');
}

/// [raw] if it is a safe in-app location to return to after signing in:
/// an absolute path (no scheme, host or `//`), not an auth screen.
String? safeReturnTo(String? raw) {
  final uri = _inAppLocation(raw);
  if (uri == null || AppRoutes.authRoutes.contains(uri.path)) return null;
  return raw!.trim();
}

/// [raw] if it is a safe place to go once the introduction is done: what
/// [safeReturnTo] accepts, or a screen for signed-out visitors (such as
/// registration).
String? safeAfterIntro(String? raw) {
  final uri = _inAppLocation(raw);
  if (uri == null) return null;
  if (AppRoutes.entryRoutes.contains(uri.path)) return raw!.trim();
  return safeReturnTo(raw);
}

/// [raw] parsed when it is an absolute in-app path (no scheme, host or
/// `//`), else null.
Uri? _inAppLocation(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();
  if (!value.startsWith('/') ||
      value.startsWith('//') ||
      value.contains(r'\')) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  return uri;
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
/// Where a link the platform handed to the router belongs, or null when
/// [location] is an ordinary route.
///
/// With Flutter's deep linking enabled the platform also pushes custom
/// scheme links as routes: Android sends only the path (`/<token>` for
/// `exevra://invite/<token>`), iOS the whole URL. The app's own link
/// handler opens these too, so both must lead to the same place.
String? platformLinkRedirect(Uri location) {
  final scheme = location.scheme.toLowerCase();
  final host = location.host.toLowerCase();
  final segments = location.pathSegments.where((s) => s.isNotEmpty).toList();
  String? inviteFor(String? token) =>
      DeepLinks.isValidToken(token) ? AppRoutes.inviteFor(token!) : null;

  if (scheme == AppConfig.inviteScheme) {
    if (host != 'invite') return AppRoutes.root;
    final token = switch (segments) {
      [final token] => token,
      [] => location.queryParameters['token'],
      _ => null,
    };
    return inviteFor(token) ?? AppRoutes.root;
  }
  if ('$scheme://$host' == AppConfig.authCallbackUrl) {
    // supabase_flutter exchanges the code; the auth phase routes on.
    return AppRoutes.root;
  }
  if (scheme.isEmpty && segments.length == 1) {
    final path = '/${segments.single}';
    final known =
        AppRoutes.authRoutes.contains(path) ||
        AppRoutes.tabs.contains(path) ||
        path == AppRoutes.invite;
    if (!known) return inviteFor(segments.single);
  }
  return null;
}

/// The redirect for [location] that the introduction needs, given whether
/// it was [completed] on this device (null while the flag loads).
///
/// * Not completed: everything except the introduction itself and
///   invitation links goes to `/onboarding`, with the location the user
///   wanted in `next` (see [safeAfterIntro]) unless that is sign-in.
/// * Loading (null) or completed: no decision here ([authRedirect] runs).
///
/// In the result, `stay` keeps the location and `to` moves there; a null
/// result leaves the decision to [authRedirect].
({bool stay, String? to})? onboardingRedirect({
  required bool? completed,
  required Uri location,
}) {
  if (completed != false) return null;
  final path = location.path.isEmpty ? AppRoutes.root : location.path;
  if (path == AppRoutes.onboarding) return (stay: true, to: null);
  if (AppRoutes.isInvite(path)) return null;
  final next = safeAfterIntro(
    path == AppRoutes.splash
        ? location.queryParameters['from']
        : location.toString(),
  );
  return (
    stay: false,
    to: next == null || next == AppRoutes.login
        ? AppRoutes.onboarding
        : '${AppRoutes.onboarding}?next=${Uri.encodeComponent(next)}',
  );
}

/// The router's redirect: platform links first, then the introduction
/// (only while [onboardingCompleted] is false), then the auth rules.
String? appRedirect({
  required AuthPhase phase,
  required Uri location,
  required bool? onboardingCompleted,
  String? pendingInviteToken,
}) {
  final link = platformLinkRedirect(location);
  if (link != null) return link;
  final intro = onboardingRedirect(
    completed: onboardingCompleted,
    location: location,
  );
  if (intro != null) return intro.stay ? null : intro.to;
  return authRedirect(
    phase: phase,
    location: location,
    pendingInviteToken: pendingInviteToken,
  );
}

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
