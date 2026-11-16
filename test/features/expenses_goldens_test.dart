import 'dart:async';

import 'package:alchemist/alchemist.dart';
import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:expense_manager/features/expenses/screens/expenses_screen.dart';
import 'package:expense_manager/l10n/l10n.dart';
import 'package:expense_manager/models/group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/golden_clock.dart';

/// Alchemist CI goldens of the expenses list in light and dark.
/// Regenerate with `flutter test --update-goldens test/features`.
void main() {
  useGoldenClock();
  late ProviderContainer container;

  setUpAll(() async {
    final backend = TestBackend(signedInAs: 'u1');
    backend.profiles.profiles['u1'] = profileOf('u1', activeGroupId: 'g1');
    backend.groups.groupsByUser['u1'] = [groupOf('g1', adminId: 'u1')];
    backend.groups.membersByGroup['g1'] = [
      memberOf('u1', role: GroupRole.admin),
      memberOf('u2'),
    ];
    backend.expenses.rows.addAll([
      expenseOf(
        'e1',
        userId: 'u1',
        groupId: 'g1',
        title: 'Dinner',
        spentAt: goldenDay(2026, 11, 16),
      ),
      expenseOf(
        'e2',
        userId: 'u2',
        groupId: 'g1',
        title: 'Cab to the airport',
        amountMinor: 64000,
        spentAt: goldenDay(2026, 11, 15),
      ).copyWith(category: 'Transport'),
      expenseOf(
        'e3',
        userId: 'u1',
        title: 'Electricity bill',
        amountMinor: 189900,
        spentAt: goldenDay(2026, 10, 28),
      ).copyWith(category: 'Utilities'),
    ]);
    container = await backend.container();
  });

  tearDownAll(() => container.dispose());

  Widget screen(ThemeData theme) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: theme,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ExpensesScreen(),
    ),
  );

  unawaited(
    goldenTest(
      'the expenses list renders in light and dark',
      fileName: 'expenses_screen',
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
                height: 720,
              ),
              child: screen(theme),
            ),
        ],
      ),
    ),
  );
}
