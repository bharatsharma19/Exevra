import 'dart:async';

import 'package:expense_manager/core/errors/app_failure.dart';
import 'package:expense_manager/core/errors/failure_messages.dart';
import 'package:expense_manager/core/widgets/widgets.dart';
import 'package:expense_manager/features/groups/widgets/settlements_card.dart';
import 'package:expense_manager/models/balance.dart';
import 'package:expense_manager/models/group.dart';
import 'package:expense_manager/models/money.dart';
import 'package:expense_manager/models/settlement.dart';
import 'package:expense_manager/providers/data_revision.dart';
import 'package:expense_manager/providers/group_detail_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/expense_group_harness.dart';
import '../support/fakes.dart';

Settlement _settlement(
  String id, {
  required String from,
  required String to,
  int amountMinor = 500,
  SettlementStatus status = SettlementStatus.pending,
  DateTime? createdAt,
}) => Settlement(
  id: id,
  groupId: 'g1',
  fromUser: from,
  toUser: to,
  amount: Money(amountMinor, 'INR'),
  status: status,
  createdAt: createdAt ?? DateTime.utc(2026, 11, 9),
);

Future<TestBackend> _pump(
  WidgetTester tester, {
  String signedInAs = 'u1',
  bool isAdmin = false,
  List<Settlement> settlements = const [],
  int u1Net = -500,
  ThemeMode mode = ThemeMode.light,
  double width = 400,
  double textScale = 1,
  void Function(TestBackend backend)? setUp,
  bool settle = true,
}) async {
  setPhoneSize(tester, width: width, height: 1400);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );

  final backend = TestBackend(signedInAs: signedInAs);
  final group = groupOf(
    'g1',
    adminId: isAdmin ? signedInAs : 'u9',
    role: isAdmin ? GroupRole.admin : GroupRole.member,
  );
  backend.profiles.profiles[signedInAs] = profileOf(
    signedInAs,
    activeGroupId: 'g1',
  );
  backend.groups.groupsByUser[signedInAs] = [group];
  backend.groups.membersByGroup['g1'] = [
    memberOf('u9', role: GroupRole.admin),
    memberOf('u1'),
    memberOf('u2'),
    memberOf('u3'),
  ];
  backend.balances.balancesByGroup['g1'] = [
    balanceOf('u2', -u1Net),
    balanceOf('u9', 0),
    balanceOf('u3', 0),
    balanceOf('u1', u1Net),
  ];
  backend.balances.suggestionsByGroup['g1'] = u1Net < 0
      ? [
          SettleSuggestion(
            fromUser: 'u1',
            toUser: 'u2',
            amount: Money(-u1Net, 'INR'),
          ),
        ]
      : const [];
  backend.settlements
    ..rows.addAll(settlements)
    ..adminId = isAdmin ? signedInAs : 'u9'
    ..maxAmountMinor = -u1Net;
  setUp?.call(backend);
  final container = await backend.container();
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: themedApp(
        mode: mode,
        textScale: textScale,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SettlementsCard(group: group),
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return backend;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('history beyond one page', () {
    late TestBackend backend;
    late ProviderContainer container;

    setUp(() async {
      backend = TestBackend(signedInAs: 'u1');
      backend.profiles.profiles['u1'] = profileOf('u1', activeGroupId: 'g1');
      backend.groups.groupsByUser['u1'] = [groupOf('g1', adminId: 'u9')];
      // An old pending payment behind 60 newer confirmed ones.
      backend.settlements.rows.add(
        _settlement('old-pending', from: 'u1', to: 'u2', amountMinor: 300),
      );
      for (var i = 0; i < 60; i++) {
        backend.settlements.rows.add(
          _settlement(
            'c${i.toString().padLeft(2, '0')}',
            from: 'u1',
            to: 'u2',
            status: SettlementStatus.confirmed,
            createdAt: DateTime.utc(2026, 11, 10).add(Duration(minutes: i)),
          ),
        );
      }
      container = await backend.container();
      addTearDown(container.dispose);
    });

    test('the cap counts pending payments outside the loaded page', () async {
      container.listen(settlementsProvider('g1'), (_, _) {});
      final history = await container
          .read(settlementsProvider('g1').notifier)
          .loaded;
      expect(history.items, hasLength(SettlementsNotifier.pageSize));
      expect(history.items.any((s) => s.id == 'old-pending'), isFalse);

      container.listen(pendingSettlementsProvider('g1'), (_, _) {});
      final pending = await container
          .read(pendingSettlementsProvider('g1').notifier)
          .loaded;
      expect(pending.map((s) => s.id), ['old-pending']);
      expect(
        settlementLimit(
          payer: 'u1',
          payee: 'u2',
          balances: [balanceOf('u1', -1000), balanceOf('u2', 1000)],
          settlements: pending,
        ),
        700,
      );
    });

    test('older payments load page by page without gaps', () async {
      container.listen(settlementsProvider('g1'), (_, _) {});
      await container.read(settlementsProvider('g1').notifier).loaded;
      expect(container.read(settlementsProvider('g1')).value!.hasMore, isTrue);

      await container.read(settlementsProvider('g1').notifier).loadMore();

      final history = container.read(settlementsProvider('g1')).value!;
      expect(history.items, hasLength(61));
      expect(history.items.map((s) => s.id).toSet(), hasLength(61));
      expect(history.items.last.id, 'old-pending');
      expect(history.hasMore, isFalse);
    });

    test('a page that lands after the list reloaded leaves no gap', () async {
      final notifier = container.read(settlementsProvider('g1').notifier);
      container.listen(settlementsProvider('g1'), (_, _) {});
      await notifier.loaded;

      final held = Completer<void>();
      backend.settlements.heldLists.add(held);
      final more = notifier.loadMore();
      await settle();

      // Three newer payments arrive and the list reloads its first page.
      for (var i = 0; i < 3; i++) {
        backend.settlements.rows.add(
          _settlement(
            'n$i',
            from: 'u2',
            to: 'u1',
            createdAt: DateTime.utc(2026, 11, 12).add(Duration(minutes: i)),
          ),
        );
      }
      container.read(dataRevisionProvider.notifier).bump(DataKind.settlements);
      await settle();
      expect(
        container.read(settlementsProvider('g1')).value!.items.first.id,
        'n2',
      );

      held.complete();
      await more;
      var history = container.read(settlementsProvider('g1')).value!;
      expect(history.isLoadingMore, isFalse);

      await notifier.loadMore();
      history = container.read(settlementsProvider('g1')).value!;
      final all = [...backend.settlements.rows]
        ..sort((a, b) {
          final t = b.createdAt.compareTo(a.createdAt);
          return t != 0 ? t : b.id.compareTo(a.id);
        });
      expect(
        history.items.map((s) => s.id),
        all.take(history.items.length).map((s) => s.id),
      );
      expect(history.items, hasLength(64));
    });
  });

  group('writes', () {
    late TestBackend backend;
    late ProviderContainer container;
    late SettlementsNotifier notifier;

    setUp(() async {
      backend = TestBackend(signedInAs: 'u1');
      backend.profiles.profiles['u1'] = profileOf('u1', activeGroupId: 'g1');
      backend.groups.groupsByUser['u1'] = [groupOf('g1', adminId: 'u9')];
      backend.settlements.rows.add(_settlement('to-me', from: 'u2', to: 'u1'));
      container = await backend.container();
      addTearDown(container.dispose);
      container.listen(settlementsProvider('g1'), (_, _) {});
      notifier = container.read(settlementsProvider('g1').notifier);
      await notifier.loaded;
    });

    test('a write that fails in transit reloads and says so', () async {
      final before = backend.settlements.listCalls;
      backend.settlements.failWrites = const AppFailure.timeout();

      final failure = await notifier.record(
        toUser: 'u2',
        amount: Money(500, 'INR'),
        report: false,
      );
      await settle();

      expect(failure, const AppFailure.network(key: 'settlement_unconfirmed'));
      expect(friendlyMessage(failure!), contains('payment'));
      expect(backend.settlements.listCalls, greaterThan(before));
    });

    test('a refused write keeps its own friendly reason', () async {
      backend.settlements.failWrites = const AppFailure.business(
        'settlement_not_pending',
      );
      final failure = await notifier.confirm('to-me');
      expect(failure, const AppFailure.business('settlement_not_pending'));
      expect(friendlyMessage(failure!), 'This payment is no longer pending.');
    });

    test('the same write is not sent twice while on its way', () async {
      final release = Completer<void>();
      backend.settlements.holdWrites = release;

      final first = notifier.confirm('to-me');
      final second = await notifier.confirm('to-me');
      expect(second, const AppFailure.business('settlement_in_progress'));
      expect(friendlyMessage(second!), contains('still being saved'));
      final recording = notifier.record(
        toUser: 'u2',
        amount: Money(500, 'INR'),
      );
      expect(
        await notifier.record(toUser: 'u2', amount: Money(500, 'INR')),
        const AppFailure.business('settlement_in_progress'),
      );

      release.complete();
      expect(await first, isNull);
      expect(await recording, isNull);
      expect(
        backend.settlements.calls.where((c) => c == 'confirm:to-me'),
        hasLength(1),
      );
      expect(
        backend.settlements.calls.where((c) => c.startsWith('record:')),
        hasLength(1),
      );
    });
  });

  group('settlementLimit', () {
    test('is what the payer owes, less pending payments', () {
      final balances = [balanceOf('a', -1000), balanceOf('b', 1000)];
      expect(
        settlementLimit(
          payer: 'a',
          payee: 'b',
          balances: balances,
          settlements: const [],
        ),
        1000,
      );
      expect(
        settlementLimit(
          payer: 'a',
          payee: 'b',
          balances: balances,
          settlements: [_settlement('p', from: 'a', to: 'b', amountMinor: 300)],
        ),
        700,
      );
      // Confirmed payments are already in the balances.
      expect(
        settlementLimit(
          payer: 'a',
          payee: 'b',
          balances: balances,
          settlements: [
            _settlement(
              'c',
              from: 'a',
              to: 'b',
              status: SettlementStatus.confirmed,
            ),
          ],
        ),
        1000,
      );
    });

    test('is capped by what the payee is owed and never negative', () {
      final balances = [
        balanceOf('a', -1000),
        balanceOf('b', 400),
        balanceOf('c', 600),
      ];
      expect(
        settlementLimit(
          payer: 'a',
          payee: 'b',
          balances: balances,
          settlements: const [],
        ),
        400,
      );
      expect(
        settlementLimit(
          payer: 'b',
          payee: 'c',
          balances: balances,
          settlements: const [],
        ),
        0,
      );
    });
  });

  testWidgets('shows each member\'s balance and the suggested payment', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Balances (INR)'), findsOneWidget);
    expect(find.text('You owe ₹5.00'), findsOneWidget);
    expect(find.text('User u2 is owed ₹5.00'), findsOneWidget);
    expect(find.text('User u9 is settled up'), findsOneWidget);
    expect(find.text('You owe User u2 ₹5.00'), findsOneWidget);
  });

  testWidgets('recording a payment leaves it pending for the payee', (
    tester,
  ) async {
    final backend = await _pump(tester);

    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();
    expect(find.text('Record a payment'), findsOneWidget);
    expect(find.text('You owe User u2 up to ₹5.00.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('payment-record')));
    await tester.pumpAndSettle();

    expect(backend.settlements.calls, ['record:u2:500']);
    expect(
      find.text('Payment recorded. It counts once User u2 confirms it.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Waiting for User u2 to confirm'),
      findsOneWidget,
    );
    expect(find.widgetWithText(StatusBadge, 'Pending'), findsOneWidget);
    // The payer can void it but cannot confirm it.
    expect(find.text('Confirm'), findsNothing);
    expect(find.text('Void'), findsOneWidget);
  });

  testWidgets('more than the debt is rejected before sending', (tester) async {
    final backend = await _pump(tester);

    await tester.tap(find.text('Record payment').first);
    await tester.pumpAndSettle();
    // u2 is chosen in the dropdown below; pick them first.
    await tester.tap(find.byKey(const Key('payment-payee')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('User u2').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('payment-amount')), '6');
    await tester.tap(find.byKey(const Key('payment-record')));
    await tester.pumpAndSettle();

    expect(find.textContaining("That's more than you owe User u2"), findsOne);
    expect(backend.settlements.calls, isEmpty);
  });

  testWidgets('nothing can be recorded to someone you do not owe', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Record payment').first);
    await tester.pumpAndSettle();
    // The first other member is the admin, who is owed nothing.
    expect(find.byKey(const Key('payment-nothing-owed')), findsOneWidget);
    final button = tester.widget<LoadingButton>(
      find.byKey(const Key('payment-record')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('a server rejection is shown in the dialog', (tester) async {
    final backend = await _pump(tester);
    backend.settlements.maxAmountMinor = 100;
    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('payment-record')));
    await tester.pumpAndSettle();

    expect(
      find.text(friendlyMessageForKey('settlement_exceeds_debt')),
      findsOneWidget,
    );
    expect(find.text('Record a payment'), findsOneWidget);
  });

  testWidgets('the payee confirms a pending payment', (tester) async {
    final backend = await _pump(
      tester,
      signedInAs: 'u2',
      u1Net: -500,
      settlements: [_settlement('s1', from: 'u1', to: 'u2')],
    );

    expect(find.textContaining('Waiting for you to confirm'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm this payment?'), findsOneWidget);
    await tester.tap(find.text('I received it'));
    await tester.pumpAndSettle();

    expect(backend.settlements.calls, ['confirm:s1']);
    expect(find.widgetWithText(StatusBadge, 'Confirmed'), findsOneWidget);
    expect(find.text('Payment confirmed.'), findsOneWidget);
    expect(find.text('Confirm'), findsNothing);
  });

  testWidgets('the payer voids a payment with a reason', (tester) async {
    final backend = await _pump(
      tester,
      settlements: [_settlement('s1', from: 'u1', to: 'u2')],
    );

    await tester.tap(find.text('Void'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('void-reason')),
      'Entered twice',
    );
    await tester.tap(find.text('Void payment'));
    await tester.pumpAndSettle();

    expect(backend.settlements.calls, ['void:s1:Entered twice']);
    expect(find.textContaining('Reason: Entered twice'), findsOneWidget);
    expect(find.widgetWithText(StatusBadge, 'Voided'), findsOneWidget);
    expect(find.text('Void'), findsNothing);
  });

  testWidgets('others see neither Confirm nor Void; the admin can void', (
    tester,
  ) async {
    await _pump(
      tester,
      signedInAs: 'u3',
      settlements: [_settlement('s1', from: 'u1', to: 'u2')],
    );
    expect(find.text('Confirm'), findsNothing);
    expect(find.text('Void'), findsNothing);
  });

  testWidgets('the group admin can void someone else\'s payment', (
    tester,
  ) async {
    await _pump(
      tester,
      signedInAs: 'u9',
      isAdmin: true,
      settlements: [_settlement('s1', from: 'u1', to: 'u2')],
    );
    expect(find.text('Confirm'), findsNothing);
    expect(find.text('Void'), findsOneWidget);
  });

  testWidgets('a payment with someone who left is locked, with the reason', (
    tester,
  ) async {
    await _pump(
      tester,
      isAdmin: true,
      settlements: [
        _settlement('gone', from: 'u1', to: 'u-left'),
        _settlement('ok', from: 'u1', to: 'u2'),
      ],
    );

    expect(find.byKey(const Key('settlement-locked-gone')), findsOneWidget);
    expect(
      find.text(friendlyMessageForKey('settlement_locked_member_left')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('settlement-void-gone')), findsNothing);
    expect(find.byKey(const Key('settlement-void-ok')), findsOneWidget);
    expect(find.byKey(const Key('settlement-locked-ok')), findsNothing);
    expect(find.textContaining('Former member'), findsWidgets);
  });

  test('isSettlementLocked waits for the members and ignores voided ones', () {
    final members = [memberOf('u1'), memberOf('u2')];
    final gone = _settlement('g', from: 'u1', to: 'u-left');
    expect(isSettlementLocked(gone, null), isFalse);
    expect(isSettlementLocked(gone, members), isTrue);
    expect(
      isSettlementLocked(_settlement('k', from: 'u1', to: 'u2'), members),
      isFalse,
    );
    expect(
      isSettlementLocked(
        _settlement(
          'v',
          from: 'u1',
          to: 'u-left',
          status: SettlementStatus.voided,
        ),
        members,
      ),
      isFalse,
    );
  });

  testWidgets('shows skeletons while balances load', (tester) async {
    final hold = Completer<void>();
    await _pump(tester, settle: false, setUp: (b) => b.reads.hold = hold);
    await tester.pump();
    expect(find.byType(SkeletonList), findsWidgets);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    hold.complete();
    await tester.pumpAndSettle();
    expect(find.text('You owe ₹5.00'), findsOneWidget);
  });

  testWidgets('a failed load offers Retry with friendly copy', (tester) async {
    final backend = await _pump(
      tester,
      setUp: (b) =>
          b.balances.gate = ReadGate()..failure = const AppFailure.offline(),
    );
    expect(find.text('Retry'), findsWidgets);
    expect(
      find.text(friendlyMessage(const AppFailure.offline())),
      findsWidgets,
    );
    backend.balances.gate.failure = null;
    await tester.tap(find.text('Retry').first);
    await tester.pumpAndSettle();
    expect(find.text('You owe ₹5.00'), findsOneWidget);
  });

  for (final mode in themeModes) {
    testWidgets('balances and payments meet the guidelines ($mode)', (
      tester,
    ) async {
      await _pump(
        tester,
        mode: mode,
        settlements: [
          _settlement('s1', from: 'u1', to: 'u2'),
          _settlement(
            's2',
            from: 'u2',
            to: 'u1',
            status: SettlementStatus.confirmed,
          ),
          _settlement('s3', from: 'u1', to: 'u-left'),
        ],
      );
      await expectAccessibleScreen(tester);
    });

    testWidgets('balances fit 320dp at 200% text ($mode)', (tester) async {
      await _pump(
        tester,
        mode: mode,
        width: 320,
        textScale: 2,
        settlements: [
          _settlement('s1', from: 'u1', to: 'u2'),
          _settlement('s3', from: 'u1', to: 'u-left'),
        ],
      );
      expectNoOverflow(tester);
      await tester.ensureVisible(find.text('Pay'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pay'));
      await tester.pumpAndSettle();
      expectNoOverflow(tester);
      expect(find.text('Record a payment'), findsOneWidget);
    });
  }
}
