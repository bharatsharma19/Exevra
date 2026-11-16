import 'dart:async';

import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:expense_manager/core/widgets/widgets.dart';
import 'package:expense_manager/data/repositories/invitation_repository.dart';
import 'package:expense_manager/features/profile/screens/invite_screen.dart';
import 'package:expense_manager/l10n/l10n.dart';
import 'package:expense_manager/models/group.dart';
import 'package:expense_manager/models/invitation.dart';
import 'package:expense_manager/providers/pending_invite_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fakes.dart';

const _token = 'Abc_DEF-123456789012345678901234567890abcde';

class _Invitations implements InvitationRepository {
  InvitationStatus status = InvitationStatus.pending;
  Duration expiresIn = const Duration(days: 3);
  AppFailure? detailsFailure;
  AppFailure? declineFailure;
  Completer<void>? holdDetails;
  final List<String> declined = [];
  final List<String> accepted = [];

  @override
  Future<InvitationDetails> details(String token) async {
    await holdDetails?.future;
    final f = detailsFailure;
    if (f != null) throw f;
    return InvitationDetails(
      invitationId: 'i1',
      groupId: 'g1',
      groupName: 'Flatmates',
      inviterName: 'Priya',
      role: GroupRole.member,
      status: status,
      expiresAt: DateTime.now().toUtc().add(expiresIn),
    );
  }

  @override
  Future<String> accept(String token) async {
    accepted.add(token);
    return 'g1';
  }

  @override
  Future<void> decline(String token) async {
    final f = declineFailure;
    if (f != null) throw f;
    declined.add(token);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

Future<void> _frames(WidgetTester tester, [int count = 6]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<(ProviderContainer, GoRouter)> _pump(
  WidgetTester tester,
  _Invitations invitations, {
  String? signedInAs = 'u1',
  ThemeMode mode = ThemeMode.light,
  Size size = const Size(400, 900),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  final backend = TestBackend(signedInAs: signedInAs);
  if (signedInAs != null) {
    backend.profiles.profiles[signedInAs] = profileOf(signedInAs);
  }
  final c = (await tester.runAsync(
    () => backend.container(
      extraOverrides: [
        invitationRepositoryProvider.overrideWithValue(invitations),
      ],
    ),
  ))!;
  addTearDown(c.dispose);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const InviteScreen(token: _token),
      ),
      GoRoute(path: '/dashboard', builder: (_, _) => const Text('dashboard')),
      GoRoute(path: '/login', builder: (_, _) => const Text('login')),
      GoRoute(path: '/register', builder: (_, _) => const Text('register')),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await _frames(tester);
  return (c, router);
}

String _location(GoRouter r) =>
    r.routerDelegate.currentConfiguration.uri.toString();

void main() {
  final states = <String, void Function(_Invitations)>{
    'pending': (_) {},
    'accepted': (i) => i.status = InvitationStatus.accepted,
    'expired': (i) => i.expiresIn = const Duration(days: -1),
    'cancelled': (i) => i.status = InvitationStatus.revoked,
    'wrong email': (i) => i.detailsFailure = const AppFailure.permissionDenied(
      key: 'invite_email_mismatch',
    ),
    'not found': (i) =>
        i.detailsFailure = const AppFailure.business('invite_not_found'),
  };

  for (final MapEntry(key: name, value: setUp) in states.entries) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('$name meets the a11y guidelines ($mode)', (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, _Invitations()..let(setUp), mode: mode);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });
    }

    testWidgets('$name fits 320dp at 200% text', (tester) async {
      await _pump(
        tester,
        _Invitations()..let(setUp),
        size: const Size(320, 640),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shows a skeleton while loading', (tester) async {
    final invitations = _Invitations()..holdDetails = Completer<void>();
    await _pump(tester, invitations);
    expect(find.byKey(const Key('invite-loading')), findsOneWidget);
    invitations.holdDetails!.complete();
    await tester.runAsync(settle);
    await _frames(tester);
    expect(find.byKey(const Key('invite-details')), findsOneWidget);
  });

  testWidgets('shows the group, the inviter and the role', (tester) async {
    await _pump(tester, _Invitations());
    expect(find.text("You're invited to Flatmates"), findsOneWidget);
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Valid until'), findsOneWidget);
  });

  testWidgets('Join accepts and opens the dashboard', (tester) async {
    final invitations = _Invitations();
    final (_, router) = await _pump(tester, invitations);
    await tester.tap(find.byKey(const Key('invite-accept')));
    await tester.runAsync(settle);
    await _frames(tester);
    expect(invitations.accepted, [_token]);
    expect(_location(router), '/dashboard');
  });

  testWidgets('Decline asks first, then declines', (tester) async {
    final invitations = _Invitations();
    final (_, router) = await _pump(tester, invitations);

    await tester.tap(find.byKey(const Key('invite-decline')));
    await _frames(tester);
    expect(find.text('Decline this invitation?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _frames(tester);
    expect(invitations.declined, isEmpty);

    await tester.tap(find.byKey(const Key('invite-decline')));
    await _frames(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(ConfirmDialog),
        matching: find.text('Decline'),
      ),
    );
    await tester.runAsync(settle);
    await _frames(tester);
    expect(invitations.declined, [_token]);
    expect(_location(router), '/dashboard');
  });

  testWidgets('a failed decline stays and explains', (tester) async {
    final invitations = _Invitations()
      ..declineFailure = const AppFailure.network();
    await _pump(tester, invitations);
    await tester.tap(find.byKey(const Key('invite-decline')));
    await _frames(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(ConfirmDialog),
        matching: find.text('Decline'),
      ),
    );
    await tester.runAsync(settle);
    await _frames(tester);
    expect(find.text("This invitation can't be opened"), findsOneWidget);
    await tester.tap(find.text('Back'));
    await _frames(tester);
    expect(find.byKey(const Key('invite-accept')), findsOneWidget);
  });

  testWidgets('another address explains who is signed in', (tester) async {
    await _pump(
      tester,
      _Invitations()
        ..detailsFailure = const AppFailure.permissionDenied(
          key: 'invite_email_mismatch',
        ),
    );
    expect(find.byKey(const Key('invite-wrong-email')), findsOneWidget);
    expect(find.textContaining("You're signed in as"), findsOneWidget);
    expect(find.byKey(const Key('invite-switch-account')), findsOneWidget);
  });

  testWidgets('signed out it keeps the invitation and asks to sign in', (
    tester,
  ) async {
    final (c, router) = await _pump(tester, _Invitations(), signedInAs: null);
    expect(find.text("You've been invited to a group"), findsOneWidget);
    expect(c.read(pendingInviteProvider), _token);
    await tester.tap(find.byKey(const Key('invite-sign-in')));
    await _frames(tester);
    expect(_location(router), '/login');
  });
}

extension<T> on T {
  T let(void Function(T) f) {
    f(this);
    return this;
  }
}
