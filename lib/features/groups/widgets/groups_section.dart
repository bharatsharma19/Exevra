import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/group.dart';
import '../../../providers/groups_provider.dart';
import '../../expenses/widgets/inline_notice.dart';
import 'active_group_card.dart';
import 'group_dialogs.dart';
import 'settlements_card.dart';

export 'active_group_card.dart';
export 'settlements_card.dart';

/// The groups area of the profile tab: the user's groups and scope, the
/// active group's members and invitations, and its balances.
class GroupsSection extends ConsumerWidget {
  const GroupsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(activeGroupProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: context.l10n.groupsTitle,
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        ),
        const MyGroupsCard(),
        if (group != null) ...[
          const SizedBox(height: AppSpacing.md),
          ActiveGroupCard(group: group),
          const SizedBox(height: AppSpacing.md),
          SettlementsCard(group: group),
        ],
      ],
    );
  }
}

/// Personal mode, the user's groups (pending requests marked), create
/// and join.
class MyGroupsCard extends ConsumerWidget {
  const MyGroupsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final groupsAsync = ref.watch(groupsProvider);
    // Only the signed-in user's groups, never a previous user's.
    final groups = ref.watch(currentGroupsProvider)?.groups ?? const <Group>[];
    final active = ref.watch(activeGroupProvider);
    final notifier = ref.read(groupsProvider.notifier);
    final loading = groupsAsync.isLoading && groups.isEmpty;
    final failed = groupsAsync.hasError && !groupsAsync.isLoading;

    void select(String? groupId) {
      AppHaptics.selection();
      unawaited(notifier.switchScope(groupId));
    }

    return AppCard(
      key: const Key('my-groups-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.groups_2_outlined,
                  size: AppSizes.iconSm,
                  color: palette.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.groupsMyGroups(groups.length),
                    style: textTheme.titleMedium?.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ),
              AppIconButton(
                key: const Key('groups-create'),
                icon: Icons.add_circle_outline_rounded,
                tooltip: l10n.groupsCreateTooltip,
                color: palette.accent,
                onPressed: () => unawaited(showCreateGroupDialog(context, ref)),
              ),
              AppIconButton(
                key: const Key('groups-join'),
                icon: Icons.group_add_outlined,
                tooltip: l10n.groupsJoinTooltip,
                color: palette.accent,
                onPressed: () => unawaited(showJoinGroupDialog(context, ref)),
              ),
            ],
          ),
          if (failed) ...[
            const SizedBox(height: AppSpacing.xs),
            CompactRetry(
              key: const Key('groups-retry'),
              error: groupsAsync.error!,
              onRetry: notifier.retry,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (loading)
            const Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                SkeletonBox(width: 140, height: 32),
                SkeletonBox(width: 96, height: 32),
              ],
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                ChoiceChip(
                  key: const Key('scope-personal'),
                  avatar: const Icon(
                    Icons.person_outline_rounded,
                    size: AppSizes.iconSm,
                  ),
                  label: Text(l10n.groupsPersonalScope),
                  selected: active == null,
                  onSelected: (_) => select(null),
                ),
                for (final g in groups)
                  Semantics(
                    label: g.isPending
                        ? l10n.groupsPendingChipLabel(g.name)
                        : null,
                    excludeSemantics: g.isPending,
                    child: ChoiceChip(
                      key: Key('scope-${g.id}'),
                      label: Text(
                        g.isPending ? l10n.groupsPendingChip(g.name) : g.name,
                      ),
                      selected: active?.id == g.id,
                      avatar: Icon(
                        g.isPending
                            ? Icons.hourglass_top_rounded
                            : Icons.groups_rounded,
                        size: AppSizes.iconSm,
                      ),
                      // A pending request opens once an admin approves.
                      onSelected: g.isPending ? null : (_) => select(g.id),
                    ),
                  ),
              ],
            ),
          if (!loading && !failed && groups.isEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _NoGroups(
              onCreate: () => unawaited(showCreateGroupDialog(context, ref)),
              onJoin: () => unawaited(showJoinGroupDialog(context, ref)),
            ),
          ],
          if (groups.any((g) => g.isPending)) ...[
            const SizedBox(height: AppSpacing.sm),
            InlineNotice(message: l10n.groupsPendingNote),
          ],
          if (!loading) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                active == null
                    ? l10n.groupsScopePersonal
                    : l10n.groupsScopeSwitched(active.name),
                key: const Key('scope-caption'),
                style: textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// First-time hint with both ways into a group.
class _NoGroups extends StatelessWidget {
  const _NoGroups({required this.onCreate, required this.onJoin});

  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      key: const Key('groups-empty'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.groupsNoGroupsTitle,
          style: textTheme.titleSmall?.copyWith(color: palette.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          l10n.groupsNoGroupsMessage,
          style: textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.groupsCreateTitle),
            ),
            OutlinedButton.icon(
              onPressed: onJoin,
              icon: const Icon(Icons.vpn_key_outlined),
              label: Text(l10n.groupsJoinTitle),
            ),
          ],
        ),
      ],
    );
  }
}
