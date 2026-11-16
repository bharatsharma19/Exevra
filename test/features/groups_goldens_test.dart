import 'dart:async';

import 'package:alchemist/alchemist.dart';
import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:expense_manager/features/groups/widgets/groups_section.dart';
import 'package:expense_manager/l10n/l10n.dart';
import 'package:expense_manager/models/balance.dart';
import 'package:expense_manager/models/group.dart';
import 'package:expense_manager/models/money.dart';
import 'package:expense_manager/models/settlement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/golden_clock.dart';

/// Alchemist CI goldens of the groups area (an admin's group with its
/// balances and payments) in light and dark.
/// Regenerate with `flutter test --update-goldens test/features`.
void main() {
  useGoldenClock();
  late ProviderContainer container;

  setUpAll(() async {
    final backend = TestBackend(signedInAs: 'u1')
      ..invitations = FakeInvitationRepository();
    final group = groupOf(
      'g1',
      adminId: 'u1',
    ).copyWith(inviteCode: 'ABCDEFGHJKMNPQRS', membersCount: 3);
    backend.profiles.profiles['u1'] = profileOf('u1', activeGroupId: 'g1');
    backend.groups.groupsByUser['u1'] = [group];
    backend.groups.membersByGroup['g1'] = [
      memberOf('u1', role: GroupRole.admin, joinedAt: goldenDay(2025, 1, 1)),
      memberOf('u2', joinedAt: goldenDay(2025, 2, 1)),
      memberOf('u3', role: GroupRole.viewer, joinedAt: goldenDay(2025, 3, 1)),
    ];
    backend.balances.balancesByGroup['g1'] = [
      balanceOf('u1', -500),
      balanceOf('u2', 500),
      balanceOf('u3', 0),
    ];
    backend.balances.suggestionsByGroup['g1'] = [
      SettleSuggestion(fromUser: 'u1', toUser: 'u2', amount: Money(500, 'INR')),
    ];
    backend.settlements
      ..adminId = 'u1'
      ..rows.addAll([
        Settlement(
          id: 's1',
          groupId: 'g1',
          fromUser: 'u2',
          toUser: 'u1',
          amount: Money(25000, 'INR'),
          status: SettlementStatus.pending,
          createdAt: goldenDay(2026, 11, 9),
        ),
        Settlement(
          id: 's2',
          groupId: 'g1',
          fromUser: 'u1',
          toUser: 'u-left',
          amount: Money(12000, 'INR'),
          status: SettlementStatus.pending,
          createdAt: goldenDay(2026, 11, 2),
        ),
      ]);
    container = await backend.container();
  });

  tearDownAll(() => container.dispose());

  Widget section(ThemeData theme) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: theme,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: GroupsSection(),
        ),
      ),
    ),
  );

  unawaited(
    goldenTest(
      'the groups area renders in light and dark',
      fileName: 'groups_section',
      builder: () => GoldenTestGroup(
        columns: 2,
        children: [
          for (final (name, theme) in [
            ('light', AppTheme.light()),
            ('dark', AppTheme.dark()),
          ])
            GoldenTestScenario(
              name: name,
              constraints: const BoxConstraints.tightFor(
                width: 360,
                height: 2000,
              ),
              child: section(theme),
            ),
        ],
      ),
    ),
  );
}
