import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/platform/connectivity.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/failure_reporter.dart';
import '../../../providers/group_detail_providers.dart';
import '../widgets/feature_snackbar.dart';

/// The signed-in frame: the offline banner above every tab, the tab content
/// and the bottom navigation bar. It also shows every background failure
/// once, as a friendly error snackbar.
class MainNavigationShell extends ConsumerWidget {
  const MainNavigationShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onTap(int index) {
    AppHaptics.selection();
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the active group's realtime channel open while signed in.
    ref.watch(groupRealtimeProvider);

    // Every background failure (save, delete, switch group...) is shown
    // here exactly once, as friendly copy. Assistant failures are shown in
    // the reply bubble only.
    ref.listen<ReportedFailure?>(failureReporterProvider, (prev, next) {
      if (next != null && next.sequence != prev?.sequence) {
        final message = friendlyMessage(
          offlineAware(next.failure, offline: ref.read(isOfflineProvider)),
        );
        if (message.isNotEmpty) {
          showFeatureSnackbar(context, message, kind: AppSnackbarKind.error);
        }
      }
    });
    final offline = ref.watch(isOfflineProvider);
    final l10n = context.l10n;
    final palette = context.palette;

    return Scaffold(
      body: Column(
        children: [
          OfflineBanner(visible: offline, message: l10n.shellOfflineMessage),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: offline,
              child: navigationShell,
            ),
          ),
        ],
      ),
      // Snack bars (shown by the root SnackbarHost) stay above the bar.
      bottomNavigationBar: SnackbarClearance(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: palette.outlineVariant)),
          ),
          child: NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _onTap,
            destinations: [
              AppNavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home_rounded),
                label: l10n.shellNavHome,
              ),
              AppNavigationDestination(
                icon: const Icon(Icons.receipt_long_outlined),
                selectedIcon: const Icon(Icons.receipt_long_rounded),
                label: l10n.shellNavExpenses,
              ),
              AppNavigationDestination(
                icon: const Icon(Icons.insert_chart_outlined_rounded),
                selectedIcon: const Icon(Icons.insert_chart_rounded),
                label: l10n.shellNavInsights,
              ),
              AppNavigationDestination(
                icon: const Icon(Icons.auto_awesome_outlined),
                selectedIcon: const Icon(Icons.auto_awesome_rounded),
                label: l10n.shellNavAssistant,
              ),
              AppNavigationDestination(
                icon: const Icon(Icons.person_outline_rounded),
                selectedIcon: const Icon(Icons.person_rounded),
                label: l10n.shellNavProfile,
              ),
            ],
          ),
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
