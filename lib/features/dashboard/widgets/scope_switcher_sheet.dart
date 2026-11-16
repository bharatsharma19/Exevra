import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/router/navigation.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/groups_provider.dart';

/// Lets the user switch the home screen between personal spending and one
/// of their approved groups.
Future<void> showScopeSwitcher(BuildContext context, WidgetRef ref) {
  AppHaptics.selection();
  return showAppSheet<void>(
    context: context,
    builder: (sheetContext) => _ScopeSwitcher(
      onManageGroups: () {
        Navigator.of(sheetContext).pop();
        goTab(context, AppRoutes.profile);
      },
    ),
  );
}

class _ScopeSwitcher extends ConsumerWidget {
  const _ScopeSwitcher({required this.onManageGroups});

  final VoidCallback onManageGroups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final palette = context.palette;
    // Pending join requests cannot be opened until an admin approves.
    final groups = ref.watch(currentGroupsProvider)?.approvedGroups ?? const [];
    final currentId = ref.watch(activeGroupProvider)?.id;

    void select(String? groupId) {
      Navigator.of(context).pop();
      if (groupId == currentId) return;
      unawaited(ref.read(groupsProvider.notifier).switchScope(groupId));
    }

    Widget option({
      required String title,
      required String subtitle,
      required IconData icon,
      required bool selected,
      required VoidCallback onTap,
      Key? key,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: AppListTile(
        key: key,
        title: title,
        subtitle: subtitle,
        selected: selected,
        onTap: onTap,
        leading: ExcludeSemantics(
          child: CircleAvatar(
            backgroundColor: selected
                ? palette.accentContainer
                : palette.surfaceVariant,
            child: Icon(
              icon,
              color: selected
                  ? palette.onAccentContainer
                  : palette.textSecondary,
            ),
          ),
        ),
        trailing: selected
            ? Icon(
                Icons.check_rounded,
                color: palette.accent,
                semanticLabel: l10n.dashboardSwitcherSelected,
              )
            : null,
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.dashboardSwitcherTitle,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: palette.textPrimary),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        option(
          key: const Key('scope-personal'),
          title: l10n.dashboardScopePersonal,
          subtitle: l10n.dashboardSwitcherPersonalSubtitle,
          icon: Icons.person_rounded,
          selected: currentId == null,
          onTap: () => select(null),
        ),
        for (final group in groups)
          option(
            key: Key('scope-${group.id}'),
            title: group.name,
            subtitle: l10n.dashboardSwitcherGroupSubtitle,
            icon: Icons.groups_rounded,
            selected: group.id == currentId,
            onTap: () => select(group.id),
          ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: onManageGroups,
          icon: const Icon(Icons.settings_outlined),
          label: Text(l10n.dashboardSwitcherManageGroups),
        ),
      ],
    );
  }
}
