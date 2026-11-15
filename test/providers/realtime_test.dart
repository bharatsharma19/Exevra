import 'package:expense_manager/data/repositories/expense_repository.dart';
import 'package:expense_manager/providers/data_revision.dart';
import 'package:expense_manager/providers/expense_provider.dart';
import 'package:expense_manager/providers/group_detail_providers.dart';
import 'package:expense_manager/providers/groups_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestBackend backend;
  late ProviderContainer container;

  setUp(() async {
    backend = TestBackend(signedInAs: 'u1');
    backend.profiles.profiles['u1'] = profileOf('u1', activeGroupId: 'g1');
    backend.groups.groupsByUser['u1'] = [groupOf('g1', adminId: 'u1')];
    backend.expenses.rows.add(expenseOf('shared', userId: 'u2', groupId: 'g1'));
    container = await backend.container();
    addTearDown(container.dispose);
    addTearDown(backend.expenses.closeRealtime);
    container
      ..listen(groupsProvider, (_, _) {})
      ..listen(groupRealtimeProvider, (_, _) {});
    await container.read(groupsProvider.notifier).loaded;
    await settle();
    final key = container.read(dashboardExpenseKeyProvider)!;
    container.listen(expenseListProvider(key), (_, _) {});
    await container.read(expenseListProvider(key).future);
  });

  // Longer than the realtime debounce.
  Future<void> afterDebounce() =>
      Future<void>.delayed(const Duration(milliseconds: 450));

  test('another member deleting a listed expense reloads the lists', () async {
    expect(backend.expenses.watchedGroups, ['g1']);
    final before = container.read(dataRevisionProvider).expenses;

    backend.expenses.rows.clear();
    backend.expenses.realtime.add(const GroupChange.expenseDeleted('shared'));
    await afterDebounce();

    expect(container.read(dataRevisionProvider).expenses, before + 1);
    final key = container.read(dashboardExpenseKeyProvider)!;
    expect(container.read(expenseListProvider(key)).value!.items, isEmpty);
  });

  test('deletions of expenses no list shows are ignored', () async {
    final before = container.read(dataRevisionProvider).expenses;

    backend.expenses.realtime.add(
      const GroupChange.expenseDeleted('someone-elses'),
    );
    await afterDebounce();

    expect(container.read(dataRevisionProvider).expenses, before);
  });
}
