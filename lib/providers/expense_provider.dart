import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_failure.dart';
import '../core/logging/app_logger.dart';
import '../core/utils/haptics.dart';
import '../data/repositories/expense_repository.dart';
import '../models/expense.dart';
import '../models/group.dart';
import '../models/json_reader.dart';
import 'auth_provider.dart';
import 'data_revision.dart';
import 'failure_reporter.dart';
import 'groups_provider.dart';

/// Which expenses the list shows within the active scope.
enum ExpenseTypeFilter { all, personal, group }

/// Filters chosen on the expenses screen. Applied on the server.
class ExpenseFilter {
  const ExpenseFilter({
    this.type = ExpenseTypeFilter.all,
    this.category,
    this.search = '',
  });

  final ExpenseTypeFilter type;

  /// Exact category, or null for all.
  final String? category;
  final String search;

  bool get isFiltered =>
      type != ExpenseTypeFilter.all || category != null || search.isNotEmpty;

  ExpenseFilter copyWith({
    ExpenseTypeFilter? type,
    Object? category = unset,
    String? search,
  }) {
    return ExpenseFilter(
      type: type ?? this.type,
      category: pick<String?>(category, this.category),
      search: search ?? this.search,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ExpenseFilter &&
      other.type == type &&
      other.category == category &&
      other.search == search;

  @override
  int get hashCode => Object.hash(type, category, search);
}

/// The expenses screen's filters. Reset when the user changes.
class ExpenseFilterNotifier extends Notifier<ExpenseFilter> {
  @override
  ExpenseFilter build() {
    ref.watch(currentUserIdProvider);
    return const ExpenseFilter();
  }

  void setType(ExpenseTypeFilter type) => state = state.copyWith(type: type);

  /// Null shows every category.
  void setCategory(String? category) =>
      state = state.copyWith(category: category);

  void setSearch(String search) =>
      state = state.copyWith(search: search.trim());

  void clear() => state = const ExpenseFilter();
}

final expenseFilterProvider =
    NotifierProvider<ExpenseFilterNotifier, ExpenseFilter>(
      ExpenseFilterNotifier.new,
    );

/// The scope for the active group (null = personal mode) and [type].
ExpenseScope scopeFor(Group? activeGroup, ExpenseTypeFilter type) {
  final group = activeGroup;
  if (group == null || !group.canRead) return const ExpenseScope.personal();
  return switch (type) {
    ExpenseTypeFilter.all => ExpenseScope.personalAndGroup(group.id),
    ExpenseTypeFilter.personal => const ExpenseScope.personal(),
    ExpenseTypeFilter.group => ExpenseScope.group(group.id),
  };
}

/// Identifies one expense list: whose it is and what it shows.
class ExpenseListKey {
  const ExpenseListKey(this.userId, this.query);

  final String userId;
  final ExpenseQuery query;

  @override
  bool operator ==(Object other) =>
      other is ExpenseListKey && other.userId == userId && other.query == query;

  @override
  int get hashCode => Object.hash(userId, query);
}

/// The unfiltered list of the active scope (dashboard, add sheet), or
/// null while signed out or while groups load.
final scopeExpenseKeyProvider = Provider<ExpenseListKey?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null || !ref.watch(groupsReadyProvider)) return null;
  final scope = scopeFor(ref.watch(activeGroupProvider), ExpenseTypeFilter.all);
  return ExpenseListKey(userId, ExpenseQuery(scope: scope));
});

/// The dashboard's list: every expense of the active (readable) group, or
/// the user's personal expenses in personal mode. It uses the same scope
/// rule as the dashboard totals (`activeInsightsKeyProvider`), so the
/// recent rows and the figures above them describe the same thing.
final dashboardExpenseKeyProvider = Provider<ExpenseListKey?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null || !ref.watch(groupsReadyProvider)) return null;
  final group = ref.watch(activeGroupProvider);
  final scope = group != null && group.canRead
      ? ExpenseScope.group(group.id)
      : const ExpenseScope.personal();
  return ExpenseListKey(userId, ExpenseQuery(scope: scope));
});

/// The expenses screen's list with its filters, or null while signed out
/// or while groups load.
final filteredExpenseKeyProvider = Provider<ExpenseListKey?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null || !ref.watch(groupsReadyProvider)) return null;
  final filter = ref.watch(expenseFilterProvider);
  final scope = scopeFor(ref.watch(activeGroupProvider), filter.type);
  return ExpenseListKey(
    userId,
    ExpenseQuery(
      scope: scope,
      category: filter.category,
      search: filter.search.isEmpty ? null : filter.search,
    ),
  );
});

/// A loaded, paged expense list.
class ExpenseListState {
  const ExpenseListState({
    this.items = const [],
    this.next,
    this.isLoadingMore = false,
    this.loadMoreFailure,
  });

  /// Newest first (`spent_at DESC, id DESC`).
  final List<Expense> items;

  /// Cursor of the next page, or null when everything is loaded.
  final ExpenseCursor? next;
  final bool isLoadingMore;

  /// Why the last "load more" failed; the first page's failure is the
  /// provider's error instead.
  final AppFailure? loadMoreFailure;

  bool get hasMore => next != null;
  bool get isEmpty => items.isEmpty;

  ExpenseListState copyWith({
    List<Expense>? items,
    Object? next = unset,
    bool? isLoadingMore,
    Object? loadMoreFailure = unset,
  }) {
    return ExpenseListState(
      items: items ?? this.items,
      next: pick<ExpenseCursor?>(next, this.next),
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreFailure: pick<AppFailure?>(loadMoreFailure, this.loadMoreFailure),
    );
  }
}

/// One expense list (keyset-paged) with optimistic writes.
///
/// * Every load carries a generation number; a result that arrives after
///   a newer load started is dropped, so only the latest load wins.
/// * Writes show immediately, are replaced by the server's row on success
///   and rolled back on failure; the failure is returned and reported once.
/// * Other lists, balances and insights reload through [dataRevisionProvider].
class ExpenseListNotifier extends AsyncNotifier<ExpenseListState> {
  ExpenseListNotifier(this.key);

  final ExpenseListKey key;

  static const int pageSize = 30;

  int _generation = 0;
  int _localIds = 0;

  /// Revision this list caused itself (already applied, no reload).
  int? _ownRevision;

  ExpenseRepository get _repo => ref.read(expenseRepositoryProvider);

  @override
  Future<ExpenseListState> build() async {
    final generation = ++_generation;
    // A list never outlives its user.
    if (ref.watch(currentUserIdProvider) != key.userId) {
      return const ExpenseListState();
    }
    final repo = ref.watch(expenseRepositoryProvider);
    ref.listen(dataRevisionProvider.select((r) => r.expenses), (_, next) {
      if (next != _ownRevision) unawaited(reload());
    });

    final page = await repo.fetchPage(
      userId: key.userId,
      query: key.query,
      limit: pageSize,
    );
    final latest = state.value;
    if (generation != _generation && latest != null) {
      // A newer reload finished first; keep its result.
      return latest;
    }
    return ExpenseListState(items: page.items, next: page.next);
  }

  /// Re-reads the list in place (as many rows as are loaded now), keeping
  /// the current rows visible. Returns the failure, or null.
  Future<AppFailure?> reload() async {
    final generation = ++_generation;
    final loaded = state.value?.items.where((e) => !e.isSyncing).length ?? 0;
    final limit = loaded < pageSize ? pageSize : loaded;
    try {
      final page = await _repo.fetchPage(
        userId: key.userId,
        query: key.query,
        limit: limit,
      );
      if (!ref.mounted || generation != _generation) return null;
      final pending = state.value?.items.where((e) => e.isSyncing) ?? const [];
      state = AsyncData(
        ExpenseListState(items: _merge(page.items, pending), next: page.next),
      );
      return null;
    } on AppFailure catch (failure) {
      if (!ref.mounted || generation != _generation) return null;
      if (state.value == null) {
        state = AsyncError(failure, StackTrace.current);
      }
      return failure;
    }
  }

  /// Loads the next page. Failures are kept in
  /// [ExpenseListState.loadMoreFailure] so the list can offer Retry.
  Future<void> loadMore() async {
    final current = state.value;
    final cursor = current?.next;
    if (current == null || cursor == null || current.isLoadingMore) return;
    final generation = _generation;
    state = AsyncData(
      current.copyWith(isLoadingMore: true, loadMoreFailure: null),
    );
    try {
      final page = await _repo.fetchPage(
        userId: key.userId,
        query: key.query,
        after: cursor,
        limit: pageSize,
      );
      if (!ref.mounted || generation != _generation) return;
      final now = state.value ?? current;
      final known = {for (final e in now.items) e.id};
      state = AsyncData(
        now.copyWith(
          items: [
            ...now.items,
            ...page.items.where((e) => !known.contains(e.id)),
          ],
          next: page.next,
          isLoadingMore: false,
        ),
      );
    } on AppFailure catch (failure) {
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(
        (state.value ?? current).copyWith(
          isLoadingMore: false,
          loadMoreFailure: failure,
        ),
      );
    }
  }

  /// Adds an expense. Returns the failure, or null when the server saved it.
  ///
  /// With [report] false the failure is only returned (for a form that
  /// shows it inline); it is still rolled back.
  Future<AppFailure?> add(ExpenseDraft draft, {bool report = true}) async {
    final invalid = draft.validate();
    if (invalid != null) return AppFailure.validation(key: invalid);
    final localId = '${Expense.localIdPrefix}${++_localIds}';
    final optimistic = draft.toOptimistic(localId: localId, userId: key.userId);
    _update((items) => _insertSorted(items, optimistic));
    try {
      final saved = await _repo.create(key.userId, draft);
      _update(
        (items) =>
            _insertSorted(items.where((e) => e.id != localId).toList(), saved),
      );
      _changed();
      AppHaptics.success();
      return null;
    } on AppFailure catch (failure) {
      _update((items) => items.where((e) => e.id != localId).toList());
      return _fail(failure, report: report);
    }
  }

  /// Saves [edited] (same id as a listed expense). Returns the failure, or
  /// null when the server saved it.
  Future<AppFailure?> edit(Expense edited, {bool report = true}) async {
    if (edited.id.startsWith(Expense.localIdPrefix)) {
      return const AppFailure.business('expense_not_saved_yet');
    }
    final before = _find(edited.id);
    _update(
      (items) => _insertSorted(
        items.where((e) => e.id != edited.id).toList(),
        edited.copyWith(isSyncing: true),
      ),
    );
    try {
      final saved = await _repo.update(edited);
      _update(
        (items) =>
            _insertSorted(items.where((e) => e.id != saved.id).toList(), saved),
      );
      _changed();
      AppHaptics.success();
      return null;
    } on AppFailure catch (failure) {
      _update((items) {
        final rest = items.where((e) => e.id != edited.id).toList();
        return before == null ? rest : _insertSorted(rest, before);
      });
      return _fail(failure, report: report);
    }
  }

  /// Deletes [expense]. Returns the failure, or null when the server
  /// deleted it.
  Future<AppFailure?> remove(Expense expense, {bool report = true}) async {
    if (expense.id.startsWith(Expense.localIdPrefix)) {
      return const AppFailure.business('expense_not_saved_yet');
    }
    final before = _find(expense.id) ?? expense;
    _update((items) => items.where((e) => e.id != expense.id).toList());
    try {
      await _repo.delete(expense.id);
      _changed();
      AppHaptics.medium();
      return null;
    } on AppFailure catch (failure) {
      _update(
        (items) => _insertSorted(
          items.where((e) => e.id != expense.id).toList(),
          before,
        ),
      );
      return _fail(failure, report: report);
    }
  }

  /// Moves [original] between personal and a group by creating [target]
  /// (the same expense with the other `groupId`) and then deleting the
  /// original; the server never changes `group_id` in place.
  ///
  /// When the original cannot be deleted, the new copy is deleted again so
  /// the expense is never counted twice. Returns the failure, or null when
  /// both writes succeeded.
  Future<AppFailure?> convert(
    Expense original,
    ExpenseDraft target, {
    bool report = true,
  }) async {
    if (original.id.startsWith(Expense.localIdPrefix)) {
      return const AppFailure.business('expense_not_saved_yet');
    }
    if (original.groupId == target.groupId) {
      return edit(
        original.copyWith(
          title: target.title.trim(),
          amount: target.amount,
          category: target.category,
          spentAt: target.spentAt.toUtc(),
          note: target.note,
        ),
        report: report,
      );
    }
    final invalid = target.validate();
    if (invalid != null) return AppFailure.validation(key: invalid);
    final before = _find(original.id) ?? original;
    final localId = '${Expense.localIdPrefix}${++_localIds}';
    final optimistic = target.toOptimistic(
      localId: localId,
      userId: key.userId,
    );
    _update(
      (items) => _insertSorted(
        items.where((e) => e.id != original.id).toList(),
        optimistic,
      ),
    );
    Expense? created;
    try {
      created = await _repo.create(key.userId, target);
      await _repo.delete(original.id);
      final saved = created;
      _update(
        (items) =>
            _insertSorted(items.where((e) => e.id != localId).toList(), saved),
      );
      _changed();
      AppHaptics.success();
      return null;
    } on AppFailure catch (failure) {
      final copy = created;
      if (copy != null) {
        try {
          await _repo.delete(copy.id);
        } on AppFailure catch (undoFailure) {
          // Both rows exist now; a reload shows them so nothing is hidden.
          AppLogger.warn('Could not remove the converted copy', undoFailure);
          _changed();
        }
      }
      _update((items) {
        final rest = items
            .where((e) => e.id != localId && e.id != original.id)
            .toList();
        return _insertSorted(rest, before);
      });
      return _fail(failure, report: report);
    }
  }

  Expense? _find(String id) {
    for (final e in state.value?.items ?? const <Expense>[]) {
      if (e.id == id) return e;
    }
    return null;
  }

  AppFailure _fail(AppFailure failure, {bool report = true}) {
    AppHaptics.error();
    if (report && ref.mounted) {
      ref.read(failureReporterProvider.notifier).report(failure);
    }
    return failure;
  }

  /// Tells other lists, balances and insights that expenses changed.
  void _changed() {
    if (!ref.mounted) return;
    final notifier = ref.read(dataRevisionProvider.notifier);
    _ownRevision = ref.read(dataRevisionProvider).expenses + 1;
    notifier.bump(DataKind.expenses);
  }

  void _update(List<Expense> Function(List<Expense> items) change) {
    if (!ref.mounted) return;
    final current = state.value ?? const ExpenseListState();
    state = AsyncData(current.copyWith(items: change(current.items)));
  }

  /// Inserts [expense] in list order if this list shows it.
  List<Expense> _insertSorted(List<Expense> items, Expense expense) {
    if (!matches(key, expense)) return items;
    final list = [...items];
    final next = state.value?.next;
    var index = list.indexWhere((e) => _before(expense, e));
    if (index < 0) {
      // Older than every loaded row: it belongs to a later page.
      if (next != null) return items;
      index = list.length;
    }
    list.insert(index, expense);
    return list;
  }

  /// Whether [a] comes before [b] (`spent_at DESC, id DESC`).
  static bool _before(Expense a, Expense b) {
    final byTime = a.spentAt.compareTo(b.spentAt);
    if (byTime != 0) return byTime > 0;
    return a.id.compareTo(b.id) > 0;
  }

  static List<Expense> _merge(List<Expense> server, Iterable<Expense> pending) {
    if (pending.isEmpty) return server;
    final list = [...server];
    for (final p in pending) {
      final index = list.indexWhere((e) => _before(p, e));
      list.insert(index < 0 ? list.length : index, p);
    }
    return list;
  }

  /// Whether the list [key] shows [expense] (mirrors the server filters).
  static bool matches(ExpenseListKey key, Expense expense) {
    final query = key.query;
    final inScope = switch (query.scope) {
      PersonalScope() => expense.isPersonal && expense.userId == key.userId,
      GroupScope(:final groupId) => expense.groupId == groupId,
      PersonalAndGroupScope(:final groupId) =>
        (expense.isPersonal && expense.userId == key.userId) ||
            expense.groupId == groupId,
    };
    if (!inScope) return false;
    final category = query.category;
    if (category != null && expense.category != category) return false;
    final search = query.search?.trim().toLowerCase();
    if (search != null &&
        search.isNotEmpty &&
        !expense.title.toLowerCase().contains(search)) {
      return false;
    }
    return true;
  }
}

/// Expense lists by owner and query. Disposed when no screen shows them.
final expenseListProvider = AsyncNotifierProvider.autoDispose
    .family<ExpenseListNotifier, ExpenseListState, ExpenseListKey>(
      ExpenseListNotifier.new,
    );
