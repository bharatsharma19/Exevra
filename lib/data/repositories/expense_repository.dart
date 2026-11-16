import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../../core/utils/date_helpers.dart';
import '../../models/expense.dart';
import '../../models/json_reader.dart';
import '../supabase_client_provider.dart';

/// Which expenses a list shows.
sealed class ExpenseScope {
  const ExpenseScope();

  /// The caller's personal expenses.
  const factory ExpenseScope.personal() = PersonalScope;

  /// Every expense of one group.
  const factory ExpenseScope.group(String groupId) = GroupScope;

  /// Personal expenses plus one group's, in one timeline.
  const factory ExpenseScope.personalAndGroup(String groupId) =
      PersonalAndGroupScope;
}

final class PersonalScope extends ExpenseScope {
  const PersonalScope();
  @override
  bool operator ==(Object other) => other is PersonalScope;
  @override
  int get hashCode => 0;
}

final class GroupScope extends ExpenseScope {
  const GroupScope(this.groupId);
  final String groupId;
  @override
  bool operator ==(Object other) =>
      other is GroupScope && other.groupId == groupId;
  @override
  int get hashCode => groupId.hashCode;
}

final class PersonalAndGroupScope extends ExpenseScope {
  const PersonalAndGroupScope(this.groupId);
  final String groupId;
  @override
  bool operator ==(Object other) =>
      other is PersonalAndGroupScope && other.groupId == groupId;
  @override
  int get hashCode => Object.hash('both', groupId);
}

/// Filters applied on the server, so pages stay complete.
class ExpenseQuery {
  const ExpenseQuery({required this.scope, this.category, this.search});

  final ExpenseScope scope;

  /// Exact category name, or null for all.
  final String? category;

  /// Case-insensitive title search, or null.
  final String? search;

  @override
  bool operator ==(Object other) =>
      other is ExpenseQuery &&
      other.scope == scope &&
      other.category == category &&
      other.search == search;

  @override
  int get hashCode => Object.hash(scope, category, search);
}

/// Keyset position: the last row of the previous page in the order
/// `spent_at DESC, id DESC`.
class ExpenseCursor {
  const ExpenseCursor(this.spentAt, this.id);

  factory ExpenseCursor.after(Expense last) =>
      ExpenseCursor(last.spentAt, last.id);

  final DateTime spentAt;
  final String id;
}

class ExpensePage {
  const ExpensePage(this.items, this.next);

  final List<Expense> items;

  /// Cursor for the following page, or null when this was the last.
  final ExpenseCursor? next;

  bool get hasMore => next != null;
}

/// Kinds of change pushed by realtime for a group.
enum GroupChangeKind { expenses, members, settlements }

/// One realtime change: a [kind] of the group's data changed, or (with
/// [deletedExpenseId]) an expense was deleted somewhere.
class GroupChange {
  const GroupChange(this.kind) : deletedExpenseId = null;

  /// An expense deletion. Realtime cannot filter deletions by group, so
  /// these arrive for any expense the server deletes, with only its id.
  const GroupChange.expenseDeleted(String id)
    : kind = GroupChangeKind.expenses,
      deletedExpenseId = id;

  final GroupChangeKind kind;
  final String? deletedExpenseId;
}

abstract interface class ExpenseRepository {
  /// One page, newest first. Throws [AppFailure].
  Future<ExpensePage> fetchPage({
    required String userId,
    required ExpenseQuery query,
    ExpenseCursor? after,
    int limit = 30,
  });

  /// Inserts and returns the saved row. Throws [AppFailure].
  Future<Expense> create(String userId, ExpenseDraft draft);

  /// Saves the editable fields and returns the saved row. Throws
  /// [AppFailure] (permission denied when no row was updated).
  Future<Expense> update(Expense expense);

  /// Deletes the expense. Throws [AppFailure] when nothing was deleted.
  Future<void> delete(String expenseId);

  /// Moves the expense to the group [groupId], or to the payer's personal
  /// expenses when it is null, in one server transaction
  /// (`move_expense_scope`). The server replaces the row: the moved
  /// expense it returns has a new id. Throws [AppFailure]; on failure the
  /// expense is unchanged.
  Future<Expense> moveScope(String expenseId, {required String? groupId});

  /// The users who share each of the group expenses [expenseIds] (their
  /// split rows; a null entry is a deleted account), in one read. An id
  /// without split rows (a personal expense) maps to an empty list.
  Future<Map<String, List<String?>>> fetchParticipants(List<String> expenseIds);

  /// Changes to a group's expenses, members and settlements, pushed by
  /// realtime, plus expense deletions (see [GroupChange.expenseDeleted]).
  /// Listening opens the channel; cancelling closes it.
  Stream<GroupChange> watchGroup(String groupId);
}

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => SupabaseExpenseRepository(ref.watch(supabaseClientProvider)),
);

class SupabaseExpenseRepository implements ExpenseRepository {
  SupabaseExpenseRepository(this._client);

  final SupabaseClient _client;

  /// Upper bound for one write, so a stalled request ends as a timeout
  /// instead of leaving the form waiting.
  static const Duration writeTimeout = Duration(seconds: 20);

  @override
  Future<ExpensePage> fetchPage({
    required String userId,
    required ExpenseQuery query,
    ExpenseCursor? after,
    int limit = 30,
  }) {
    return ErrorMapper.guard(() async {
      var request = _client.from('expenses').select(Expense.columns);

      final clauses = <String>[];
      switch (query.scope) {
        case PersonalScope():
          request = request.eq('user_id', userId).isFilter('group_id', null);
        case GroupScope(:final groupId):
          request = request.eq('group_id', groupId);
        case PersonalAndGroupScope(:final groupId):
          clauses.add(
            'or(and(user_id.eq.${_quote(userId)},group_id.is.null),'
            'group_id.eq.${_quote(groupId)})',
          );
      }
      if (after != null) {
        final at = _quote(DateHelpers.toUtcIso(after.spentAt));
        clauses.add(
          'or(spent_at.lt.$at,and(spent_at.eq.$at,id.lt.${_quote(after.id)}))',
        );
      }
      if (clauses.length == 1) {
        // or(x) with a single child is x itself.
        request = request.or(_unwrapOr(clauses.single));
      } else if (clauses.length > 1) {
        request = request.or('and(${clauses.join(',')})');
      }

      final category = query.category;
      if (category != null) request = request.eq('category', category);
      final search = _likePattern(query.search);
      if (search != null) request = request.ilike('title', search);

      final rows = await request
          .order('spent_at', ascending: false)
          .order('id', ascending: false)
          .limit(limit + 1);
      final items = parseList(rows, Expense.fromJson, 'Expense');
      if (items.length <= limit) return ExpensePage(items, null);
      final page = items.sublist(0, limit);
      return ExpensePage(page, ExpenseCursor.after(page.last));
    });
  }

  @override
  Future<Expense> create(String userId, ExpenseDraft draft) {
    return ErrorMapper.guard(() async {
      final invalid = draft.validate();
      if (invalid != null) throw AppFailure.validation(key: invalid);
      final row = await _client
          .from('expenses')
          .insert(draft.toInsertJson(userId))
          .select(Expense.columns)
          .single()
          .timeout(writeTimeout);
      return Expense.fromJson(row);
    });
  }

  @override
  Future<Expense> update(Expense expense) {
    return ErrorMapper.guard(() async {
      final rows = await _client
          .from('expenses')
          .update(expense.toUpdateJson())
          .eq('id', expense.id)
          .select(Expense.columns)
          .timeout(writeTimeout);
      return Expense.fromJson(requireRows(rows).first);
    });
  }

  @override
  Future<void> delete(String expenseId) {
    return ErrorMapper.guard(() async {
      final rows = await _client
          .from('expenses')
          .delete()
          .eq('id', expenseId)
          .select('id')
          .timeout(writeTimeout);
      requireRows(rows);
    });
  }

  @override
  Future<Expense> moveScope(String expenseId, {required String? groupId}) {
    return ErrorMapper.guard(() async {
      final data = await _client
          .rpc<Object?>(
            'move_expense_scope',
            params: {'p_expense_id': expenseId, 'p_group_id': groupId},
          )
          .timeout(writeTimeout);
      return Expense.fromJson(singleResult(data));
    });
  }

  @override
  Future<Map<String, List<String?>>> fetchParticipants(
    List<String> expenseIds,
  ) {
    return ErrorMapper.guard(() async {
      final result = {for (final id in expenseIds) id: <String?>[]};
      if (expenseIds.isEmpty) return result;
      final rows = await _client
          .from('expense_splits')
          .select('expense_id, user_id')
          .inFilter('expense_id', expenseIds);
      for (final row in rows) {
        final split = JsonReader.of(row, 'Split');
        result[split.string('expense_id')]?.add(split.optString('user_id'));
      }
      return result;
    });
  }

  @override
  Stream<GroupChange> watchGroup(String groupId) {
    late final RealtimeChannel channel;
    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'group_id',
      value: groupId,
    );
    final controller = StreamController<GroupChange>();
    controller
      ..onListen = () {
        channel = _client.channel('group-changes:$groupId');
        for (final (table, kind) in const [
          ('expenses', GroupChangeKind.expenses),
          ('group_members', GroupChangeKind.members),
          ('settlements', GroupChangeKind.settlements),
        ]) {
          channel.onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            filter: filter,
            callback: (_) {
              if (!controller.isClosed) controller.add(GroupChange(kind));
            },
          );
        }
        // Postgres Changes never apply a filter to DELETE events (the old
        // record carries only the primary key), so deletions are watched
        // unfiltered and matched against the lists on screen by id.
        channel.onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'expenses',
          callback: (payload) {
            final id = payload.oldRecord['id'];
            if (id is String && !controller.isClosed) {
              controller.add(GroupChange.expenseDeleted(id));
            }
          },
        );
        channel.subscribe();
      }
      ..onCancel = () async {
        await _client.removeChannel(channel);
        await controller.close();
      };
    return controller.stream;
  }

  /// Double-quotes a value for a PostgREST logic tree (timestamps contain
  /// `:` and `.`, which are reserved there).
  static String _quote(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  static String _unwrapOr(String clause) =>
      clause.startsWith('or(') && clause.endsWith(')')
      ? clause.substring(3, clause.length - 1)
      : clause;

  /// `%term%` with LIKE wildcards in the user's text escaped.
  static String? _likePattern(String? search) {
    final term = search?.trim();
    if (term == null || term.isEmpty) return null;
    final escaped = term
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_')
        .replaceAll('*', '');
    return '%$escaped%';
  }
}
