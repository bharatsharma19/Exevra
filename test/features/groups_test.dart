import 'dart:async';

import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/errors/failure_messages.dart';
import 'package:expense_manager/core/widgets/widgets.dart';
import 'package:expense_manager/features/groups/widgets/groups_section.dart';
import 'package:expense_manager/models/group.dart';
import 'package:expense_manager/models/invitation.dart';
import 'package:expense_manager/providers/groups_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/expense_group_harness.dart';
import '../support/fakes.dart';

Future<(TestBackend, ProviderContainer)> _pump(
  WidgetTester tester, {
  Group? group,
  List<GroupMember> members = const [],
  void Function(TestBackend backend)? setUp,
  ThemeMode mode = ThemeMode.light,
  double width = 400,
  double height = 1600,
  double textScale = 1,
  bool settle = true,
}) async {
  setPhoneSize(tester, width: width, height: height);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );

  final backend = TestBackend(signedInAs: 'u1')
    ..invitations = FakeInvitationRepository();
  backend.profiles.profiles['u1'] = profileOf('u1', activeGroupId: group?.id);
  if (group != null) {
    backend.groups.groupsByUser['u1'] = [group];
    backend.groups.membersByGroup[group.id] = [...members];
  }
  setUp?.call(backend);
  final container = await backend.container();
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: themedApp(
        mode: mode,
        textScale: textScale,
        home: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: GroupsSection(),
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return (backend, container);
}

Group _adminGroup() => groupOf(
  'g1',
  adminId: 'u1',
).copyWith(inviteCode: 'ABCDEFGHJKMNPQRS', membersCount: 3);

List<GroupMember> _members() => [
  memberOf('u1', role: GroupRole.admin, joinedAt: DateTime.utc(2025)),
  memberOf('u2', joinedAt: DateTime.utc(2025, 2)),
  memberOf('u3', role: GroupRole.viewer, joinedAt: DateTime.utc(2025, 3)),
  memberOf('u4', role: GroupRole.viewer, status: MemberStatus.pending),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('my groups', () {
    testWidgets('creates a group with a fixed currency and opens it', (
      tester,
    ) async {
      final (backend, container) = await _pump(tester);

      await tester.tap(find.byKey(const Key('groups-create')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('group-name')), 'Flatmates');
      await tester.tap(find.byKey(const Key('group-currency')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('EUR (€)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(backend.groups.calls, ['create:Flatmates:EUR']);
      expect(container.read(activeGroupProvider)?.name, 'Flatmates');
      expect(backend.groups.activeGroupWrites, ['new-1']);
      expect(find.textContaining('"Flatmates" created'), findsOneWidget);
    });

    testWidgets('a created group that cannot be opened closes the form', (
      tester,
    ) async {
      final (backend, _) = await _pump(tester);
      backend.groups.failSetActive = const AppFailure.network();

      await tester.tap(find.byKey(const Key('groups-create')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('group-name')), 'Trip');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      // No form left to press Create on again.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('"Trip" was created'), findsOneWidget);
      expect(backend.groups.calls, ['create:Trip:INR']);
    });

    testWidgets('an unconfirmed create says to check before retrying', (
      tester,
    ) async {
      final (backend, _) = await _pump(tester);
      backend.groups
        ..failCreate = const AppFailure.timeout()
        ..createBeforeFailing = true;

      await tester.tap(find.byKey(const Key('groups-create')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('group-name')), 'Trip');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.text(friendlyMessageForKey('group_unconfirmed')),
        findsOneWidget,
      );
      expect(find.text('Group Trip'), findsNothing);
      expect(find.text('Trip'), findsWidgets);
    });

    testWidgets('a blank name is rejected inline', (tester) async {
      final (backend, _) = await _pump(tester);
      await tester.tap(find.byKey(const Key('groups-create')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.text(friendlyMessageForKey('invalid_group_name')), findsOne);
      expect(backend.groups.calls, isEmpty);
    });

    testWidgets('joining by code says it waits for approval', (tester) async {
      final (backend, _) = await _pump(tester);

      await tester.tap(find.byKey(const Key('groups-join')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('join-code')), 'abcd-efgh');
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      expect(backend.groups.calls, ['join:abcd-efgh']);
      expect(find.textContaining('once an admin approves you'), findsOneWidget);
      expect(find.text('Group joined (waiting for approval)'), findsOneWidget);
    });

    testWidgets('a wrong code is explained in the dialog', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('groups-join')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('join-code')), 'BAD-CODE');
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();

      expect(find.text(friendlyMessageForKey('invalid_code')), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  group('admin', () {
    testWidgets('approves a join request as a viewer', (tester) async {
      final (backend, _) = await _pump(
        tester,
        group: _adminGroup(),
        members: _members(),
      );

      expect(find.text('Waiting for approval (1)'), findsOneWidget);
      await tester.tap(find.byTooltip('Approve User u4'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve as viewer (read only)'));
      await tester.pumpAndSettle();

      expect(backend.groups.calls, ['approve:u4:viewer']);
      expect(find.text('Waiting for approval (1)'), findsNothing);
    });

    testWidgets('denies a join request after confirming', (tester) async {
      final (backend, _) = await _pump(
        tester,
        group: _adminGroup(),
        members: _members(),
      );
      await tester.tap(find.byTooltip('Deny User u4'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Deny'));
      await tester.pumpAndSettle();
      expect(backend.groups.calls, ['remove:u4:false']);
    });

    testWidgets('changes a member to viewer', (tester) async {
      final (backend, _) = await _pump(
        tester,
        group: _adminGroup(),
        members: _members(),
      );
      await tester.tap(find.byTooltip('Manage User u2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make viewer (read only)'));
      await tester.pumpAndSettle();
      // Taking a right away asks first.
      expect(find.text('Make User u2 a viewer?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Make viewer'));
      await tester.pumpAndSettle();
      expect(backend.groups.calls, ['role:u2:viewer']);
      expect(find.text('User u2 can now only view the group.'), findsOneWidget);
    });

    testWidgets('hands over admin after confirming', (tester) async {
      final (backend, _) = await _pump(
        tester,
        group: _adminGroup(),
        members: _members(),
      );
      await tester.tap(find.byTooltip('Manage User u2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make admin'));
      await tester.pumpAndSettle();
      expect(find.text('Make User u2 the admin?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Make admin'));
      await tester.pumpAndSettle();
      expect(backend.groups.calls, ['transfer:u2']);
    });

    testWidgets('removing an unsettled member asks before forcing', (
      tester,
    ) async {
      final (backend, _) = await _pump(
        tester,
        group: _adminGroup(),
        members: _members(),
        setUp: (b) => b.groups.unsettled.add('u2'),
      );
      await tester.tap(find.byTooltip('Manage User u2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from group'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(find.text('User u2 is not settled up'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove anyway'));
      await tester.pumpAndSettle();
      expect(backend.groups.calls, ['remove:u2:false', 'remove:u2:true']);
      expect(find.text('User u2 was removed from the group.'), findsOneWidget);
    });

    testWidgets('a new invite code is confirmed and can be shared', (
      tester,
    ) async {
      final (backend, _) = await _pump(
        tester,
        group: _adminGroup(),
        members: _members(),
      );
      expect(find.text('ABCD-EFGH-JKMN-PQRS'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'New code'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'New code'));
      await tester.pumpAndSettle();
      expect(backend.groups.calls, ['rotate:g1']);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(backend.share.shared.single, contains('NEWC-0DE0-NEWC-0DE0'));
    });

    testWidgets('leaving as admin names the next admin', (tester) async {
      final (backend, _) = await _pump(
        tester,
        group: _adminGroup(),
        members: _members(),
      );
      await tester.tap(find.byKey(const Key('group-leave')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('User u2, the longest-standing member, becomes'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Leave group'));
      await tester.pumpAndSettle();
      expect(backend.groups.calls, ['leave:g1']);
    });
  });

  group('invitations', () {
    Future<void> invite(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Invite by email'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('invite-email')),
        'Friend+exevra@Example.com',
      );
      await tester.tap(find.text('Send invitation'));
      await tester.pumpAndSettle();
    }

    testWidgets('says "Email sent" only when the server sent it', (
      tester,
    ) async {
      final (backend, _) = await _pump(
        tester,
        group: _adminGroup(),
        members: _members(),
      );
      await invite(tester);

      expect(backend.invitations!.sentTo, ['friend+exevra@example.com']);
      expect(
        find.text('Email sent to friend+exevra@example.com.'),
        findsOneWidget,
      );
      expect(find.text("Couldn't send the email"), findsNothing);
      // The new invitation is listed as pending.
      expect(find.text('Pending invitations (1)'), findsOneWidget);
    });

    testWidgets('offers the link to share when the email failed', (
      tester,
    ) async {
      const link = 'https://exevra.app/invite/tok_1234567890abcdef';
      final (backend, _) = await _pump(
        tester,
        group: _adminGroup(),
        members: _members(),
        setUp: (b) => b.invitations!.nextSend = const SentInvitation(
          invitationId: 'inv-2',
          sent: false,
          reason: 'email_failed',
          shareUrl: link,
        ),
      );
      await invite(tester);

      expect(find.text("Couldn't send the email"), findsOneWidget);
      expect(find.textContaining('Email sent'), findsNothing);
      expect(find.text(link), findsOneWidget);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(backend.share.shared.single, contains(link));
    });

    testWidgets('lists only pending invitations and revokes one', (
      tester,
    ) async {
      final now = DateTime.now().toUtc();
      GroupInvitation inv(String id, InvitationStatus status, Duration ttl) =>
          GroupInvitation(
            id: id,
            groupId: 'g1',
            inviterId: 'u1',
            email: '$id@example.com',
            role: GroupRole.member,
            status: status,
            expiresAt: now.add(ttl),
            createdAt: now,
          );
      final (backend, _) = await _pump(
        tester,
        group: _adminGroup(),
        members: _members(),
        setUp: (b) => b.invitations!.pending.addAll([
          inv('open', InvitationStatus.pending, const Duration(days: 3)),
          inv('old', InvitationStatus.pending, const Duration(days: -1)),
          inv('done', InvitationStatus.accepted, const Duration(days: 3)),
        ]),
      );

      expect(find.text('Pending invitations (1)'), findsOneWidget);
      expect(find.text('open@example.com'), findsOneWidget);
      expect(find.text('old@example.com'), findsNothing);
      expect(find.text('done@example.com'), findsNothing);

      await tester.tap(find.byTooltip('Revoke invitation'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Revoke'));
      await tester.pumpAndSettle();
      expect(backend.invitations!.revoked, ['open']);
      expect(find.text('open@example.com'), findsNothing);
      expect(
        find.text('Invitation for open@example.com revoked.'),
        findsOneWidget,
      );
    });
  });

  group('states', () {
    testWidgets('a new user is shown both ways into a group', (tester) async {
      await _pump(tester);
      expect(find.byKey(const Key('groups-empty')), findsOneWidget);
      expect(find.text('Share costs with a group'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Join with a code'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('join-code')), findsOneWidget);
    });

    testWidgets('shows skeletons while groups load', (tester) async {
      final hold = Completer<void>();
      await _pump(tester, settle: false, setUp: (b) => b.reads.hold = hold);
      await tester.pump();
      expect(find.byType(SkeletonBox), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      hold.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('groups-empty')), findsOneWidget);
    });

    testWidgets('a failed load offers Retry', (tester) async {
      final (backend, _) = await _pump(
        tester,
        group: _adminGroup(),
        members: _members(),
        setUp: (b) => b.groups.failFetch = const AppFailure.offline(),
      );
      expect(find.byKey(const Key('groups-retry')), findsOneWidget);
      backend.groups.failFetch = null;
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('groups-retry')),
          matching: find.text('Retry'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('groups-retry')), findsNothing);
      expect(find.text('Group g1'), findsWidgets);
    });

    testWidgets('the group summary names its currency', (tester) async {
      await _pump(tester, group: _adminGroup(), members: _members());
      expect(find.text('Currency INR · 3 members'), findsOneWidget);
      expect(find.text('Balances (INR)'), findsOneWidget);
      expect(find.text('Showing expenses from Group g1'), findsOneWidget);
    });

    testWidgets('an invitation that was neither sent nor linked says so', (
      tester,
    ) async {
      await _pump(
        tester,
        group: _adminGroup(),
        members: _members(),
        setUp: (b) => b.invitations!.nextSend = const SentInvitation(
          invitationId: 'inv-3',
          sent: false,
          reason: 'email_failed',
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Invite by email'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('invite-email')),
        'a@example.com',
      );
      await tester.tap(find.text('Send invitation'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Email sent'), findsNothing);
      expect(find.textContaining("couldn't email it"), findsOneWidget);
    });

    testWidgets('deleting a group with other members is refused', (
      tester,
    ) async {
      final (backend, _) = await _pump(
        tester,
        group: _adminGroup(),
        members: _members(),
      );
      await tester.tap(find.byKey(const Key('group-delete')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Remove the other members'), findsOneWidget);
      expect(backend.groups.calls, isEmpty);
    });
  });

  for (final mode in themeModes) {
    testWidgets('an admin group meets the guidelines ($mode)', (tester) async {
      await _pump(
        tester,
        mode: mode,
        group: _adminGroup(),
        members: _members(),
      );
      await expectAccessibleScreen(tester);
    });

    testWidgets('a new user meets the guidelines ($mode)', (tester) async {
      await _pump(tester, mode: mode);
      await expectAccessibleScreen(tester);
    });

    testWidgets('groups fit 320dp at 200% text ($mode)', (tester) async {
      await _pump(
        tester,
        mode: mode,
        width: 320,
        height: 800,
        textScale: 2,
        group: _adminGroup(),
        members: _members(),
      );
      expectNoOverflow(tester);
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Invite by email'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Invite by email'));
      await tester.pumpAndSettle();
      expectNoOverflow(tester);
      expect(find.byKey(const Key('invite-email')), findsOneWidget);
    });
  }
}
