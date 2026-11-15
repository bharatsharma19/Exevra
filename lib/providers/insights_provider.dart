import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_failure.dart';
import '../core/platform/device_time_zone.dart';
import '../data/repositories/insights_repository.dart';
import '../models/insights.dart';
import 'auth_provider.dart';
import 'data_revision.dart';
import 'groups_provider.dart';
import 'profile_provider.dart';

/// Timeframe chosen on the insights screen. Reset when the user changes.
class InsightsTimeframeNotifier extends Notifier<InsightTimeframe> {
  @override
  InsightTimeframe build() {
    ref.watch(currentUserIdProvider);
    return InsightTimeframe.month;
  }

  void set(InsightTimeframe timeframe) => state = timeframe;
}

final insightsTimeframeProvider =
    NotifierProvider<InsightsTimeframeNotifier, InsightTimeframe>(
      InsightsTimeframeNotifier.new,
    );

/// What one insights request covers.
class InsightsKey {
  const InsightsKey({
    required this.userId,
    required this.scope,
    required this.timeframe,
    this.groupId,
  });

  final String userId;
  final InsightScope scope;
  final InsightTimeframe timeframe;

  /// Set for group scope only.
  final String? groupId;

  @override
  bool operator ==(Object other) =>
      other is InsightsKey &&
      other.userId == userId &&
      other.scope == scope &&
      other.timeframe == timeframe &&
      other.groupId == groupId;

  @override
  int get hashCode => Object.hash(userId, scope, timeframe, groupId);
}

/// Insights for the active scope: the group when one is active (and
/// readable), otherwise personal. Null while signed out or while groups
/// load. Pass a [InsightTimeframe] to pick the window.
final activeInsightsKeyProvider =
    Provider.family<InsightsKey?, InsightTimeframe>((ref, timeframe) {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null || !ref.watch(groupsReadyProvider)) return null;
      final group = ref.watch(activeGroupProvider);
      final inGroup = group != null && group.canRead;
      return InsightsKey(
        userId: userId,
        scope: inGroup ? InsightScope.group : InsightScope.personal,
        timeframe: timeframe,
        groupId: inGroup ? group.id : null,
      );
    });

/// Server-side spending summary, bucketed in the device time zone.
/// Reloads when expenses change.
final insightsProvider = FutureProvider.autoDispose
    .family<ExpenseInsights, InsightsKey>((ref, key) async {
      if (ref.watch(currentUserIdProvider) != key.userId) {
        throw const AppFailure.sessionExpired();
      }
      ref.watch(dataRevisionProvider.select((r) => r.expenses));
      ref.watch(dataRevisionProvider.select((r) => r.settlements));
      final repo = ref.watch(insightsRepositoryProvider);
      final currency = ref.watch(preferredCurrencyProvider);
      final zone = await ref.watch(deviceTimeZoneProvider.future);
      return repo.fetch(
        scope: key.scope,
        timeframe: key.timeframe,
        timeZone: zone,
        preferredCurrency: currency,
        groupId: key.groupId,
      );
    });
