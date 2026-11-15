import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/haptics.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/errors/failure_messages.dart';
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
        _showError(context, friendlyMessage(next.failure));
      }
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: navigationShell,
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
