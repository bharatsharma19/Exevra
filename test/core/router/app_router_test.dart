import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/router/app_router.dart';
import 'package:expense_manager/data/repositories/invitation_repository.dart';
import 'package:expense_manager/features/auth/screens/login_screen.dart';
import 'package:expense_manager/features/profile/screens/invite_screen.dart';
import 'package:expense_manager/main.dart';
import 'package:expense_manager/models/group.dart';
import 'package:expense_manager/models/invitation.dart';
import 'package:expense_manager/providers/pending_invite_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

const _token = 'Abc_DEF-123456789012345678901234567890abcde';

class _FakeInvitations implements InvitationRepository {
  AppFailure? detailsFailure;

  @override
  Future<InvitationDetails> details(String token) async {
    final f = detailsFailure;
    if (f != null) throw f;
    return InvitationDetails(
      invitationId: 'i1',
      groupId: 'g1',
      groupName: 'Flatmates',
      role: GroupRole.member,
      status: InvitationStatus.pending,
      expiresAt: DateTime.now().toUtc().add(const Duration(days: 3)),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  late TestBackend backend;
  late FakeLinkSource links;
  late _FakeInvitations invitations;

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    String? signedInAs,
    Uri? initialLink,
  }) async {
    backend = TestBackend(signedInAs: signedInAs);
    if (signedInAs != null) {
      backend.profiles.profiles[signedInAs] = profileOf(signedInAs);
    }
    links = FakeLinkSource(initial: initialLink);
    backend.links = links;
    invitations = _FakeInvitations();
    final container = (await tester.runAsync(
      () => backend.container(
        extraOverrides: [
          invitationRepositoryProvider.overrideWithValue(invitations),
        ],
      ),
    ))!;
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const ExevraApp()),
    );
    await _settle(tester);
    return container;
  }

  String location(ProviderContainer c) =>
      c.read(routerProvider).routerDelegate.currentConfiguration.uri.toString();

  testWidgets('a signed-out cold start shows login, not the dashboard', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    expect(location(c), '/login');
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('an unknown location shows the not-found page', (tester) async {
    final c = await pumpApp(tester, signedInAs: 'A');
    c.read(routerProvider).go('/no/such/page');
    await _settle(tester);
    expect(find.text("We couldn't find that page"), findsOneWidget);
    await tester.tap(find.text('Go to Home'));
    await _settle(tester);
    expect(location(c), '/dashboard');
  });

  testWidgets('a cold-start invite link survives signing in', (tester) async {
    final c = await pumpApp(
      tester,
      initialLink: Uri.parse('exevra://invite/$_token'),
    );
    expect(location(c), '/invite/$_token');
    expect(find.byType(InviteScreen), findsOneWidget);
    expect(c.read(pendingInviteProvider), _token);

    // The user signs in from the login screen.
    c.read(routerProvider).go('/login');
    await _settle(tester);
    expect(location(c), '/login');

    backend.profiles.profiles['A'] = profileOf('A');
    backend.auth.signInAs('A');
    await _settle(tester);
    expect(location(c), '/invite/$_token');
    expect(find.text('Flatmates'), findsOneWidget);
    // Seen by the signed-in user: no longer pending.
    expect(c.read(pendingInviteProvider), isNull);
  });

  testWidgets('a legacy ?token= invite location is rewritten', (tester) async {
    final c = await pumpApp(tester, signedInAs: 'A');
    c.read(routerProvider).go('/invite?token=$_token');
    await _settle(tester);
    expect(location(c), '/invite/$_token');
  });

  testWidgets('another address explains and offers to switch account', (
    tester,
  ) async {
    final c = await pumpApp(tester, signedInAs: 'A');
    invitations.detailsFailure = const AppFailure.permissionDenied(
      key: 'invite_email_mismatch',
    );
    c.read(routerProvider).go('/invite/$_token');
    await _settle(tester);
    expect(find.textContaining("You're signed in as A@example.com"), findsOne);
    await tester.tap(find.text('Sign out and use the invited address'));
    await _settle(tester);
    expect(c.read(pendingInviteProvider), _token);
    expect(backend.auth.signOutCalls, 1);
  });
}

/// Pumps frames without waiting for endless animations (spinners).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
