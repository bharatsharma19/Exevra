import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_failure.dart';
import '../core/logging/app_logger.dart';
import '../core/utils/haptics.dart';
import '../data/repositories/expense_repository.dart';
import '../data/repositories/group_repository.dart';
import '../models/expense.dart';
import '../models/group.dart';
import '../models/json_reader.dart';
import 'auth_provider.dart';
import 'data_revision.dart';
import 'session_guard.dart';
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

/// The expense lists that are alive, so a realtime deletion (which
/// carries only the row's id) can be matched against what is on screen.
class ExpenseListRegistry {
  final Set<ExpenseListNotifier> _lists = {};

  /// Whether any live list shows the expense [id].
  bool shows(String id) => _lists.any((list) => list.contains(id));
}

final expenseListRegistryProvider = Provider<ExpenseListRegistry>(
  (ref) => ExpenseListRegistry(),
);

/// The outcome of [ExpenseListNotifier.move]: the moved expense (with its
/// new server id) or the failure.
typedef MoveResult = ({Expense? moved, AppFailure? failure});

/// One expense list (keyset-paged) with optimistic writes.
///
/// * Every load carries a generation number; a result that arrives after
///   a newer load started is dropped, so only the latest load wins.
/// * A page requested before one of this list's writes was confirmed may
///   predate it, so it is fetched again instead of being shown.
/// * A next page is only appended to the list it continues; when the list
///   was reloaded meanwhile the page is dropped (and "loading more" ends,
///   also when that reload failed).
/// * An add still waiting for its answer may already be on the server
///   when a reload (for example after a realtime change) lands first; its
///   row is not shown next to the optimistic one.
/// * Writes show immediately, are replaced by the server's row on success
///   and rolled back on failure; the failure is returned and reported once.
/// * Other lists, balances and insights reload through [dataRevisionProvider].
/// * Every action captures the session it starts in (see [SessionGuard]);
///   when that session ended meanwhile its result is dropped: no state
///   change, no follow-up call (a move after a saved edit would run with the
///   next user's token) and no report.
class ExpenseListNotifier extends AsyncNotifier<ExpenseListState> {
  ExpenseListNotifier(this.key);

  final ExpenseListKey key;

  static const int pageSize = 30;

  int _generation = 0;
  int _localIds = 0;

  /// Moves whenever the server confirms a write made through this list.
  int _confirmed = 0;

  /// Ids deleted through this list (pending or confirmed). Ids are never
  /// reused, so pages are filtered against this for the list's lifetime.
  final Set<String> _deleted = {};

  /// Revision this list caused itself (already applied, no reload).
  int? _ownRevision;

  ExpenseRepository get _repo => ref.read(expenseRepositoryProvider);

  /// The session an action of this list starts in.
  SessionGuard _session() => SessionGuard.start(() => ref);

  /// Whether the result of [action], started in [session], may still be
  /// applied: the session holds and is the one of this list's user.
  bool _holds(SessionGuard session, String action) =>
      session.userId == key.userId && session.holds(action);

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
    final registry = ref.read(expenseListRegistryProvider);
    registry._lists.add(this);
    ref.onDispose(() => registry._lists.remove(this));

    ExpensePage page;
    int confirmed;
    do {
      confirmed = _confirmed;
      page = await repo.fetchPage(
        userId: key.userId,
        query: key.query,
        limit: pageSize,
      );
    } while (confirmed != _confirmed && ref.mounted);
    final latest = state.value;
    if (generation != _generation && latest != null) {
      // A newer reload finished first; keep its result.
      return latest;
    }
    return ExpenseListState(
      items: _merge(page.items, _pending(latest), known: _shown(latest)),
      next: page.next,
    );
  }

  /// Whether this list currently shows the expense [id].
  bool contains(String id) =>
      state.value?.items.any((e) => e.id == id) ?? false;

  /// Rows still waiting for the server (optimistic adds and edits).
  static Iterable<Expense> _pending(ExpenseListState? state) =>
      state?.items.where((e) => e.isSyncing) ?? const <Expense>[];

  /// Ids of the server rows [state] shows.
  static Set<String> _shown(ExpenseListState? state) => {
    for (final e in state?.items ?? const <Expense>[])
      if (!e.isSyncing) e.id,
  };

  /// Re-reads the list in place (as many rows as are loaded now), keeping
  /// the current rows visible. Returns the failure, or null.
  Future<AppFailure?> reload() async {
    const action = 'an expense list reload';
    final session = _session();
    final generation = ++_generation;
    final confirmed = _confirmed;
    final loaded = state.value?.items.where((e) => !e.isSyncing).length ?? 0;
    final limit = loaded < pageSize ? pageSize : loaded;
    try {
      final page = await _repo.fetchPage(
        userId: key.userId,
        query: key.query,
        limit: limit,
      );
      if (!_holds(session, action) || generation != _generation) return null;
      // A write was confirmed while this page was on its way, so the page
      // may not include it: read again.
      if (confirmed != _confirmed) return reload();
      state = AsyncData(
        ExpenseListState(
          items: _merge(
            page.items,
            _pending(state.value),
            known: _shown(state.value),
          ),
          next: page.next,
        ),
      );
      return null;
    } on AppFailure catch (failure) {
      if (!_holds(session, action) || generation != _generation) return null;
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
    const action = 'an expense page';
    final session = _session();
    final generation = _generation;
    final confirmed = _confirmed;
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
      if (!_holds(session, action)) return;
      final now = state.value;
      if (generation != _generation ||
          now == null ||
          !_sameCursor(now.next, cursor)) {
        _endLoadingMore();
        return;
      }
      final known = {for (final e in now.items) e.id, ..._deleted};
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
      // The page may predate a write confirmed meanwhile.
      if (confirmed != _confirmed) unawaited(reload());
    } on AppFailure catch (failure) {
      if (!_holds(session, action)) return;
      final now = state.value;
      if (generation != _generation ||
          now == null ||
          !_sameCursor(now.next, cursor)) {
        _endLoadingMore();
        return;
      }
      state = AsyncData(
        now.copyWith(isLoadingMore: false, loadMoreFailure: failure),
      );
    }
  }

  static bool _sameCursor(ExpenseCursor? a, ExpenseCursor b) =>
      a != null && a.id == b.id && a.spentAt == b.spentAt;

  /// Ends "loading more" for a page that was dropped.
  void _endLoadingMore() {
    final now = state.value;
    if (!ref.mounted || now == null || !now.isLoadingMore) return;
    state = AsyncData(now.copyWith(isLoadingMore: false));
  }

  /// Adds an expense. Returns the failure, or null when the server saved it.
  ///
  /// With [report] false the failure is only returned (for a form that
  /// shows it inline); it is still rolled back.
  Future<AppFailure?> add(ExpenseDraft draft, {bool report = true}) async {
    final invalid = draft.validate();
    if (invalid != null) return AppFailure.validation(key: invalid);
    const action = 'an expense add';
    final session = _session();
    if (!_holds(session, action)) return SessionGuard.dropped;
    final localId = '${Expense.localIdPrefix}${++_localIds}';
    final optimistic = draft.toOptimistic(localId: localId, userId: key.userId);
    _update((items) => _insertSorted(items, optimistic));
    try {
      final saved = await _repo.create(key.userId, draft);
      if (!_holds(session, action)) return SessionGuard.dropped;
      _confirmed++;
      _update(
        (items) => _insertSorted(
          items.where((e) => e.id != localId && e.id != saved.id).toList(),
          saved,
        ),
      );
      _changed();
      AppHaptics.success();
      return null;
    } on AppFailure catch (failure) {
      if (!_holds(session, action)) return SessionGuard.dropped;
      _update((items) => items.where((e) => e.id != localId).toList());
      // A create that failed in transit may still have been saved, and the
      // server assigns ids, so a blind retry could add the expense twice.
      return session.fail(
        _inTransit(failure) ? _unconfirmed() : failure,
        action,
        report: report,
      );
    }
  }

  /// Every list reloads to show what the server has, and the failure says
  /// so instead of inviting a retry.
  AppFailure _unconfirmed() {
    _reloadAll();
    return const AppFailure.network(key: 'expense_unconfirmed');
  }

  /// Whether [failure] leaves open if the request reached the server.
  static bool _inTransit(AppFailure failure) => failure.outcomeUnknown;

  /// Saves [edited] (same id as a listed expense). Returns the failure, or
  /// null when the server saved it.
  Future<AppFailure?> edit(Expense edited, {bool report = true}) async {
    if (edited.id.startsWith(Expense.localIdPrefix)) {
      return const AppFailure.business('expense_not_saved_yet');
    }
    const action = 'an expense edit';
    final session = _session();
    if (!_holds(session, action)) return SessionGuard.dropped;
    final before = _find(edited.id);
    _update(
      (items) => _insertSorted(
        items.where((e) => e.id != edited.id).toList(),
        edited.copyWith(isSyncing: true),
      ),
    );
    try {
      final saved = await _repo.update(edited);
      if (!_holds(session, action)) return SessionGuard.dropped;
      _confirmed++;
      _update(
        (items) =>
            _insertSorted(items.where((e) => e.id != saved.id).toList(), saved),
      );
      _changed();
      AppHaptics.success();
      return null;
    } on AppFailure catch (failure) {
      if (!_holds(session, action)) return SessionGuard.dropped;
      _update((items) {
        final rest = items.where((e) => e.id != edited.id).toList();
        return before == null ? rest : _insertSorted(rest, before);
      });
      _reloadIfInTransit(failure);
      return session.fail(failure, action, report: report);
    }
  }

  /// Deletes [expense]. Returns the failure, or null when the server
  /// deleted it.
  Future<AppFailure?> remove(Expense expense, {bool report = true}) async {
    if (expense.id.startsWith(Expense.localIdPrefix)) {
      return const AppFailure.business('expense_not_saved_yet');
    }
    const action = 'an expense delete';
    final session = _session();
    if (!_holds(session, action)) return SessionGuard.dropped;
    final before = _find(expense.id) ?? expense;
    _deleted.add(expense.id);
    _update((items) => items.where((e) => e.id != expense.id).toList());
    try {
      await _repo.delete(expense.id);
      if (!_holds(session, action)) return SessionGuard.dropped;
      _confirmed++;
      _changed();
      AppHaptics.medium();
      return null;
    } on AppFailure catch (failure) {
      // Undo the local bookkeeping even when the result is dropped, so a
      // later session on this instance does not keep the row hidden.
      _deleted.remove(expense.id);
      if (!_holds(session, action)) return SessionGuard.dropped;
      _reloadIfInTransit(failure);
      _update(
        (items) => _insertSorted(
          items.where((e) => e.id != expense.id).toList(),
          before,
        ),
      );
      return session.fail(failure, action, report: report);
    }
  }

  /// Saves [target] for [original] when it belongs to another scope
  /// (personal <-> group, or another group). The expense is moved with one
  /// server call (`move_expense_scope`), so it is never counted twice or
  /// lost, and changed fields are saved with a separate update:
  ///
  /// * from personal, before the move, because a group only accepts an
  ///   expense in its own currency;
  /// * from a group, after the move, because a group row refuses a new
  ///   currency and an edit saved there first would change the group's
  ///   balances even if the move then failed.
  ///
  /// Shows the result at once and rolls back on failure. Returns the moved
  /// expense (the server gives it a new id) or the failure. When the edit
  /// was saved but the move failed, the edit stays; when the move worked
  /// but the edit after it failed, both [MoveResult.moved] and
  /// [MoveResult.failure] are set.
  Future<MoveResult> move(
    Expense original,
    ExpenseDraft target, {
    bool report = true,
  }) async {
    if (original.id.startsWith(Expense.localIdPrefix)) {
      return const (
        moved: null,
        failure: AppFailure.business('expense_not_saved_yet'),
      );
    }
    final edited = original.copyWith(
      title: target.title.trim(),
      amount: target.amount,
      category: target.category,
      spentAt: target.spentAt.toUtc(),
      note: target.note,
      isSyncing: false,
    );
    if (original.groupId == target.groupId) {
      return (moved: null, failure: await edit(edited, report: report));
    }
    final invalid = target.validate();
    if (invalid != null) {
      return (moved: null, failure: AppFailure.validation(key: invalid));
    }
    return _move(
      original,
      groupId: target.groupId,
      edited: _sameFields(edited, original) ? null : edited,
      report: report,
    );
  }

  /// Moves [expense] to the group [groupId] (null = personal) as it is, for
  /// example to undo a move. See [move].
  Future<MoveResult> moveTo(
    Expense expense, {
    required String? groupId,
    bool report = true,
  }) async {
    if (expense.id.startsWith(Expense.localIdPrefix)) {
      return const (
        moved: null,
        failure: AppFailure.business('expense_not_saved_yet'),
      );
    }
    if (expense.groupId == groupId) {
      return (
        moved: null,
        failure: const AppFailure.validation(key: 'expense_scope_unchanged'),
      );
    }
    return _move(expense, groupId: groupId, report: report);
  }

  Future<MoveResult> _move(
    Expense original, {
    required String? groupId,
    Expense? edited,
    required bool report,
  }) async {
    const action = 'an expense move';
    final session = _session();
    if (!_holds(session, action)) {
      return (moved: null, failure: SessionGuard.dropped);
    }
    final before = _find(original.id) ?? original;
    // Shown in its new scope until the server answers (the list drops it
    // when it does not show that scope).
    final optimistic = (edited ?? original).copyWith(
      groupId: groupId,
      isSyncing: true,
    );
    _update(
      (items) => _insertSorted(
        items.where((e) => e.id != original.id).toList(),
        optimistic,
      ),
    );
    final editFirst = edited != null && original.isPersonal;
    Expense? savedEdit;
    final Expense moved;
    try {
      if (editFirst) {
        savedEdit = await _repo.update(edited);
        if (!_holds(session, action)) {
          return (moved: null, failure: SessionGuard.dropped);
        }
        _confirmed++;
      }
      moved = await _repo.moveScope(original.id, groupId: groupId);
      if (!_holds(session, action)) {
        return (moved: null, failure: SessionGuard.dropped);
      }
      _confirmed++;
      _deleted.add(original.id);
    } on AppFailure catch (failure) {
      if (!_holds(session, action)) {
        return (moved: null, failure: SessionGuard.dropped);
      }
      final unsure = _inTransit(failure);
      _update(
        (items) => _insertSorted(
          items.where((e) => e.id != original.id).toList(),
          savedEdit ?? before,
        ),
      );
      // A saved edit changed the data even though the move failed.
      if (savedEdit != null && !unsure) _changed();
      return (
        moved: null,
        failure: session.fail(
          unsure ? _unconfirmed() : _moveFailure(failure),
          action,
          report: report,
        ),
      );
    }

    var shown = moved;
    AppFailure? editFailure;
    if (edited != null && !editFirst) {
      // The moved row is now in its new scope, which accepts the edit.
      try {
        shown = await _repo.update(
          moved.copyWith(
            title: edited.title,
            amount: edited.amount,
            category: edited.category,
            spentAt: edited.spentAt,
            note: edited.note,
          ),
        );
        if (!_holds(session, action)) {
          return (moved: null, failure: SessionGuard.dropped);
        }
        _confirmed++;
      } on AppFailure catch (failure) {
        if (!_holds(session, action)) {
          return (moved: null, failure: SessionGuard.dropped);
        }
        editFailure = failure;
      }
    }
    _update(
      (items) => _insertSorted(
        items.where((e) => e.id != original.id && e.id != moved.id).toList(),
        shown,
      ),
    );
    _changed();
    if (editFailure != null) {
      // Moved, but the changed fields were not saved.
      return (
        moved: moved,
        failure: session.fail(
          _inTransit(editFailure) ? _unconfirmed() : editFailure,
          'an expense edit',
          report: report,
        ),
      );
    }
    AppHaptics.success();
    return (moved: shown, failure: null);
  }

  /// `invalid_target` from a move means the expense is already there.
  static AppFailure _moveFailure(AppFailure failure) =>
      failure.key == 'invalid_target'
      ? const AppFailure.validation(key: 'expense_scope_unchanged')
      : failure;

  /// Whether [a] and [b] hold the same editable fields.
  static bool _sameFields(Expense a, Expense b) =>
      a.title == b.title &&
      a.amount == b.amount &&
      a.category == b.category &&
      a.spentAt.isAtSameMomentAs(b.spentAt) &&
      a.note == b.note;

  Expense? _find(String id) {
    for (final e in state.value?.items ?? const <Expense>[]) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// After a failure in transit the write may still have happened, so
  /// every list reloads to show the server's state.
  void _reloadIfInTransit(AppFailure failure) {
    if (_inTransit(failure)) _reloadAll();
  }

  /// Makes every list (this one included), balances and insights reload.
  void _reloadAll() {
    if (!ref.mounted) return;
    ref.read(dataRevisionProvider.notifier).bump(DataKind.expenses);
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

  /// [server] rows plus the rows still waiting for the server. A pending
  /// edit wins over the server's copy of the same id, and rows deleted
  /// through this list stay hidden.
  ///
  /// An optimistic add whose answer has not arrived may already be one of
  /// the [server] rows. A row this list did not show before ([known]) with
  /// the same content is taken to be it and is not shown twice; the answer
  /// then replaces the optimistic row by the server's id.
  ///
  /// Accepted limit: an identical row saved on another device meanwhile
  /// is matched the same way and stays hidden until the next reload after
  /// the add's answer (then both rows show, by their ids).
  List<Expense> _merge(
    List<Expense> server,
    Iterable<Expense> pending, {
    Set<String> known = const {},
  }) {
    final hidden = {..._deleted, for (final p in pending) p.id};
    for (final p in pending) {
      if (!p.id.startsWith(Expense.localIdPrefix)) continue;
      for (final e in server) {
        if (known.contains(e.id) || hidden.contains(e.id)) continue;
        if (_sameContent(p, e)) {
          hidden.add(e.id);
          break;
        }
      }
    }
    final list = [
      for (final e in server)
        if (!hidden.contains(e.id)) e,
    ];
    for (final p in pending) {
      final index = list.indexWhere((e) => _before(p, e));
      list.insert(index < 0 ? list.length : index, p);
    }
    return list;
  }

  /// Whether [server] holds what the optimistic [local] row was created
  /// with (the server keeps instants to the second at least).
  static bool _sameContent(Expense local, Expense server) =>
      local.userId == server.userId &&
      local.groupId == server.groupId &&
      local.title == server.title &&
      local.amount == server.amount &&
      local.category == server.category &&
      local.spentAt.difference(server.spentAt).inMilliseconds.abs() < 1000;

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

/// Identifies a group expense for [expenseLockedProvider].
typedef ExpenseLockKey = ({String expenseId, String groupId, String? payerId});

/// The [ExpenseLockKey] of [expense], or null for a personal expense
/// (which is never locked) or one that is not saved yet.
ExpenseLockKey? expenseLockKeyOf(Expense expense) {
  final groupId = expense.groupId;
  if (groupId == null || expense.id.startsWith(Expense.localIdPrefix)) {
    return null;
  }
  return (expenseId: expense.id, groupId: groupId, payerId: expense.userId);
}

/// Collects the lock checks asked for in one turn of the event loop (the
/// rows of one list frame) into a single participants read.
class ExpenseParticipantsBatcher {
  ExpenseParticipantsBatcher(this._repo);

  final ExpenseRepository _repo;
  final Map<String, Completer<List<String?>>> _queued = {};
  final Map<String, Future<List<String?>>> _inFlight = {};

  /// The participants of [expenseId], read together with the others
  /// asked for in the same turn.
  Future<List<String?>> fetch(String expenseId) {
    final running = _inFlight[expenseId];
    if (running != null) return running;
    final queued = _queued[expenseId];
    if (queued != null) return queued.future;
    if (_queued.isEmpty) Timer.run(_flush);
    return (_queued[expenseId] = Completer<List<String?>>()).future;
  }

  Future<void> _flush() async {
    final batch = Map.of(_queued);
    _queued.clear();
    for (final MapEntry(:key, :value) in batch.entries) {
      _inFlight[key] = value.future;
    }
    try {
      final result = await _repo.fetchParticipants(batch.keys.toList());
      for (final MapEntry(:key, :value) in batch.entries) {
        value.complete(result[key] ?? const []);
      }
    } on Object catch (error, stack) {
      for (final completer in batch.values) {
        completer.completeError(error, stack);
      }
    } finally {
      batch.keys.forEach(_inFlight.remove);
    }
  }
}

/// See [ExpenseParticipantsBatcher]. Lives while any lock check does.
final expenseParticipantsBatcherProvider =
    Provider.autoDispose<ExpenseParticipantsBatcher>(
      (ref) => ExpenseParticipantsBatcher(ref.watch(expenseRepositoryProvider)),
    );

/// A group's members for the lock checks: read once per group and shared
/// by every row, again after joins, leaves and removals.
final expenseLockMembersProvider = FutureProvider.autoDispose
    .family<List<GroupMember>, String>((ref, groupId) {
      ref.watch(currentUserIdProvider);
      ref.watch(dataRevisionProvider.select((r) => r.members));
      return ref.watch(groupRepositoryProvider).fetchMembers(groupId);
    });

/// Whether a group expense is locked because someone who shares it (the
/// payer or anyone in its split) is no longer an approved member of the
/// group. The server then refuses amount and payer changes, deletion and
/// moves (`expense_locked_member_left`); title, category, note and date
/// stay editable.
///
/// The rows of a list share their reads: one participants read per frame
/// ([ExpenseParticipantsBatcher]) and one members read per group
/// ([expenseLockMembersProvider]).
///
/// False while signed out and when the check itself fails: the server
/// still enforces the rule, and its error is shown then.
final expenseLockedProvider = FutureProvider.autoDispose
    .family<bool, ExpenseLockKey>((ref, key) async {
      if (ref.watch(currentUserIdProvider) == null) return false;
      // Joins, leaves and removals change the answer.
      ref.watch(dataRevisionProvider.select((r) => r.members));
      final participants = ref
          .watch(expenseParticipantsBatcherProvider)
          .fetch(key.expenseId);
      final members = ref.watch(expenseLockMembersProvider(key.groupId).future);
      try {
        final (who, approved) = await (participants, members).wait;
        // No visible members: the caller cannot tell (for example after
        // leaving); the server decides.
        if (approved.isEmpty) return false;
        return isExpenseLocked(
          payerId: key.payerId,
          participants: who,
          members: approved,
        );
      } on ParallelWaitError<Object?, Object?> catch (error) {
        AppLogger.warn(
          'Could not check whether an expense is locked',
          error.errors,
        );
        return false;
      }
    });

/// The rule behind [expenseLockedProvider]: locked when the payer or any
/// participant is a deleted account (null) or not an approved member.
/// Viewers still count as members.
bool isExpenseLocked({
  required String? payerId,
  required List<String?> participants,
  required List<GroupMember> members,
}) {
  final approved = {
    for (final m in members)
      if (m.status == MemberStatus.approved) m.userId,
  };
  return [
    payerId,
    ...participants,
  ].any((id) => id == null || !approved.contains(id));
}
