import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Counters that move whenever server data of one kind changed (a write
/// from this device or a realtime event). Lists, balances and insights
/// watch the counter they depend on and reload when it moves.
class DataRevision {
  const DataRevision({
    this.expenses = 0,
    this.members = 0,
    this.settlements = 0,
  });

  final int expenses;
  final int members;
  final int settlements;
}

enum DataKind { expenses, members, settlements }

class DataRevisionNotifier extends Notifier<DataRevision> {
  @override
  DataRevision build() => const DataRevision();

  /// Marks [kind] as changed and returns its new revision.
  int bump(DataKind kind) {
    final s = state;
    state = switch (kind) {
      DataKind.expenses => DataRevision(
        expenses: s.expenses + 1,
        members: s.members,
        settlements: s.settlements,
      ),
      DataKind.members => DataRevision(
        expenses: s.expenses,
        members: s.members + 1,
        settlements: s.settlements,
      ),
      DataKind.settlements => DataRevision(
        expenses: s.expenses,
        members: s.members,
        settlements: s.settlements + 1,
      ),
    };
    return switch (kind) {
      DataKind.expenses => state.expenses,
      DataKind.members => state.members,
      DataKind.settlements => state.settlements,
    };
  }
}

final dataRevisionProvider =
    NotifierProvider<DataRevisionNotifier, DataRevision>(
      DataRevisionNotifier.new,
    );
