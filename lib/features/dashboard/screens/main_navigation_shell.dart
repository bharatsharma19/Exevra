import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/haptics.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/platform/connectivity.dart';
import '../../../providers/chat_provider.dart';
import '../../../providers/failure_reporter.dart';
import '../../../providers/group_detail_providers.dart';

class MainNavigationShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const MainNavigationShell({super.key, required this.navigationShell});

  void _onTap(int index) {
    AppHaptics.selection();
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  void _showError(BuildContext context, String message) {
    if (message.isEmpty) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.onError),
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the active group's realtime channel open while signed in.
    ref.watch(groupRealtimeProvider);

    // Every background failure (save, delete, switch group...) is shown
    // here exactly once, as friendly copy.
    ref.listen<ReportedFailure?>(failureReporterProvider, (prev, next) {
      if (next != null && next.sequence != prev?.sequence) {
        _showError(
          context,
          friendlyMessage(
            offlineAware(next.failure, offline: ref.read(isOfflineProvider)),
          ),
        );
      }
    });
    final offline = ref.watch(isOfflineProvider);

    ref.listen<ChatState>(chatProvider, (prev, next) {
      if (next.errorMessage != null &&
          (prev?.errorMessage != next.errorMessage)) {
        _showError(context, next.errorMessage!);
      }
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Column(
        children: [
          if (offline) const OfflineBanner(),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: offline,
              child: navigationShell,
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              width: 1,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _onTap,
          backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
          indicatorColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: 0.2),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(
                Icons.dashboard_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: const Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(
                Icons.receipt_long_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              label: 'Expenses',
            ),
            NavigationDestination(
              icon: const Icon(Icons.insert_chart_outlined_rounded),
              selectedIcon: Icon(
                Icons.insert_chart_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              label: 'Insights',
            ),
            const NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.primaryViolet,
              ),
              label: 'AI Advisor',
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(
                Icons.person_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

/// A transport failure while the device is offline is explained as
/// "you're offline" rather than as a server problem.
AppFailure offlineAware(AppFailure failure, {required bool offline}) {
  if (!offline) return failure;
  return switch (failure) {
    NetworkFailure() || TimeoutFailure() => const AppFailure.offline(),
    _ => failure,
  };
}

/// Shown above every tab while the device has no connection.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Material(
        key: const Key('offline-banner'),
        color: scheme.inverseSurface,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 18,
                  color: scheme.onInverseSurface,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "You're offline. Changes can't be saved until you "
                    'reconnect.',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onInverseSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
