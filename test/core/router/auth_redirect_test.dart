import 'package:expense_manager/core/router/app_routes.dart';
import 'package:expense_manager/providers/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? go(AuthPhase phase, String location, {String? invite}) =>
      authRedirect(
        phase: phase,
        location: Uri.parse(location),
        pendingInviteToken: invite,
      );

  const token = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG';

  group('initializing', () {
    test('only the splash screen, keeping the target', () {
      expect(go(AuthPhase.initializing, '/splash'), isNull);
      expect(go(AuthPhase.initializing, '/login'), '/splash');
      expect(
        go(AuthPhase.initializing, '/expenses'),
        '/splash?from=%2Fexpenses',
      );
      expect(go(AuthPhase.initializing, '/'), '/splash');
    });
  });

  group('signedOut', () {
    test('entry screens and invitations stay', () {
      for (final path in [
        '/login',
        '/register',
        '/forgot-password',
        '/invite/$token',
      ]) {
        expect(go(AuthPhase.signedOut, path), isNull, reason: path);
      }
    });

    test('everything else goes to login with returnTo', () {
      expect(go(AuthPhase.signedOut, '/'), '/login');
      expect(go(AuthPhase.signedOut, '/splash'), '/login');
      expect(go(AuthPhase.signedOut, '/verify-email'), '/login');
      expect(go(AuthPhase.signedOut, '/reset-password'), '/login');
      expect(
        go(AuthPhase.signedOut, '/dashboard'),
        '/login?returnTo=%2Fdashboard',
      );
      expect(
        go(AuthPhase.signedOut, '/splash?from=%2Finsights'),
        '/login?returnTo=%2Finsights',
      );
    });

    test('an invitation opened at cold start is shown', () {
      expect(
        go(
          AuthPhase.signedOut,
          '/splash?from=${Uri.encodeComponent('/invite/$token')}',
        ),
        '/invite/$token',
      );
    });
  });

  group('needsEmailVerification', () {
    test('only the verification screen', () {
      expect(go(AuthPhase.needsEmailVerification, '/verify-email'), isNull);
      for (final path in ['/', '/login', '/dashboard', '/invite/$token']) {
        expect(
          go(AuthPhase.needsEmailVerification, path),
          '/verify-email',
          reason: path,
        );
      }
    });
  });

  group('recoveringPassword', () {
    test('only the new-password screen', () {
      expect(go(AuthPhase.recoveringPassword, '/reset-password'), isNull);
      for (final path in [
        '/',
        '/dashboard',
        '/profile',
        '/login',
        '/verify-email',
        '/invite/$token',
      ]) {
        expect(
          go(AuthPhase.recoveringPassword, path),
          '/reset-password',
          reason: path,
        );
      }
    });
  });

  group('signedIn', () {
    test('app screens and invitations stay', () {
      for (final path in [
        '/dashboard',
        '/expenses',
        '/profile',
        '/invite/$token',
      ]) {
        expect(go(AuthPhase.signedIn, path), isNull, reason: path);
      }
    });

    test('auth screens go to the dashboard', () {
      for (final path in [
        '/',
        '/splash',
        '/login',
        '/register',
        '/forgot-password',
        '/verify-email',
        '/reset-password',
      ]) {
        expect(go(AuthPhase.signedIn, path), '/dashboard', reason: path);
      }
    });

    test('returnTo is honoured only for safe in-app paths', () {
      expect(
        go(AuthPhase.signedIn, '/login?returnTo=%2Finsights'),
        '/insights',
      );
      expect(go(AuthPhase.signedIn, '/splash?from=%2Fchat'), '/chat');
      for (final bad in [
        'https://evil.example',
        '//evil.example',
        r'/\evil',
        '/login',
        'dashboard',
      ]) {
        expect(
          go(AuthPhase.signedIn, '/login?returnTo=${Uri.encodeComponent(bad)}'),
          '/dashboard',
          reason: bad,
        );
      }
    });

    test('a pending invitation wins after sign-in', () {
      expect(go(AuthPhase.signedIn, '/login', invite: token), '/invite/$token');
      expect(go(AuthPhase.signedIn, '/dashboard', invite: token), isNull);
    });
  });
}
