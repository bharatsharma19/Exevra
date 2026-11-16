import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/date_helpers.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/group.dart';
import '../../../models/invitation.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/group_detail_providers.dart';
import '../../../providers/groups_provider.dart';
import '../../expenses/widgets/inline_notice.dart';
import 'group_dialogs.dart';
import 'group_member_tiles.dart';

/// The active group: its currency and members, the invite code and email
/// invitations (admin), join requests, roles, and leave or delete.
class ActiveGroupCard extends ConsumerWidget {
  const ActiveGroupCard({super.key, required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final userId = ref.watch(currentUserIdProvider);
    final membersAsync = ref.watch(groupMembersProvider(group.id));
    final members = membersAsync.value ?? const <GroupMember>[];
    final approved = members.where((m) => !m.isPending).toList();
    final requests = members.where((m) => m.isPending).toList();
    final now = DateTime.now();
    final invitations = !group.isAdmin
        ? const <GroupInvitation>[]
        : (ref.watch(pendingInvitationsProvider(group.id)).value ??
                  const <GroupInvitation>[])
              .where((i) => i.isPendingAt(now))
              .toList();

    Widget section(String title) => SectionHeader(
      title: title,
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
    );

    return AppCard(
      key: const Key('active-group-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                header: true,
                child: Text(
                  group.name,
                  style: textTheme.titleLarge?.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
              StatusBadge(
                group.isAdmin
                    ? StatusBadgeKind.admin
                    : group.isViewer
                    ? StatusBadgeKind.viewer
                    : StatusBadgeKind.member,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.groupsSummary(group.currency, group.membersCount),
            key: const Key('group-summary'),
            style: textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
          ),
          if (group.isViewer) ...[
            const SizedBox(height: AppSpacing.md),
            InlineNotice(message: l10n.groupsViewerNote),
          ],
          if (group.isAdmin) ...[
            const SizedBox(height: AppSpacing.md),
            _InviteCodeRow(group: group),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  onPressed: () =>
                      unawaited(showInviteByEmailDialog(context, ref, group)),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: Text(l10n.groupsInviteByEmail),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_rotateCode(context, ref)),
                  icon: const Icon(Icons.autorenew_rounded),
                  label: Text(l10n.groupsNewCode),
                ),
              ],
            ),
          ],
          if (invitations.isNotEmpty) ...[
            section(l10n.groupsPendingInvitations(invitations.length)),
            for (final inv in invitations)
              InvitationTile(group: group, invitation: inv),
          ],
          if (membersAsync.hasError && members.isEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            CompactRetry(
              error: membersAsync.error!,
              onRetry: () => ref.invalidate(groupMembersProvider(group.id)),
            ),
          ] else if (membersAsync.isLoading && members.isEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            const SkeletonList(itemCount: 3, padding: EdgeInsets.zero),
          ],
          if (group.isAdmin && requests.isNotEmpty) ...[
            section(l10n.groupsWaitingForApproval(requests.length)),
            for (final m in requests) JoinRequestTile(group: group, member: m),
          ],
          if (approved.isNotEmpty) ...[
            section(l10n.groupsMembers(approved.length)),
            for (final m in approved)
              MemberTile(group: group, member: m, isSelf: m.userId == userId),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              TextButton.icon(
                key: const Key('group-leave'),
                onPressed: () => unawaited(_leave(context, ref, approved)),
                icon: const Icon(Icons.exit_to_app_rounded),
                label: Text(l10n.groupsLeave),
              ),
              if (group.isAdmin)
                TextButton.icon(
                  key: const Key('group-delete'),
                  onPressed: () =>
                      unawaited(_delete(context, ref, approved.length)),
                  style: TextButton.styleFrom(foregroundColor: palette.danger),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(l10n.groupsDelete),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _rotateCode(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await confirmAction(
      context,
      title: l10n.groupsNewCodeTitle,
      message: l10n.groupsNewCodeMessage,
      confirmLabel: l10n.groupsNewCode,
    );
    if (!ok || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final (code, failure) = await ref
        .read(groupsProvider.notifier)
        .rotateInviteCode(group.id);
    if (code == null || failure != null || !context.mounted) return;
    AppSnackbar.show(
      l10n.groupsNewCodeReady(code.display),
      kind: AppSnackbarKind.success,
      messenger: messenger,
      action: SnackBarAction(
        label: l10n.groupsShare,
        onPressed: () =>
            unawaited(shareInviteCode(context, ref, group, code.display)),
      ),
    );
  }

  Future<void> _leave(
    BuildContext context,
    WidgetRef ref,
    List<GroupMember> approved,
  ) async {
    final l10n = context.l10n;
    final userId = ref.read(currentUserIdProvider);
    final String message;
    if (group.isAdmin) {
      // The server passes admin to the longest-standing approved member.
      final others = approved.where((m) => m.userId != userId).toList()
        ..sort((a, b) {
          final at = a.joinedAt, bt = b.joinedAt;
          if (at != null && bt != null && at != bt) return at.compareTo(bt);
          return a.userId.compareTo(b.userId);
        });
      message = others.isEmpty
          ? l10n.groupsLeaveLastMessage(group.name)
          : l10n.groupsLeaveAdminMessage(others.first.label);
    } else {
      message = l10n.groupsLeaveMessage(group.name);
    }
    final ok = await confirmAction(
      context,
      title: l10n.groupsLeaveTitle(group.name),
      message: message,
      confirmLabel: l10n.groupsLeave,
      destructive: true,
    );
    if (!ok) return;
    // A failure (for example an open balance) is shown once by the shell.
    await ref.read(groupsProvider.notifier).leaveGroup(group.id);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    int approvedCount,
  ) async {
    final l10n = context.l10n;
    if (approvedCount > 1) {
      showMessage(context, l10n.groupsDeleteHasMembers);
      return;
    }
    final ok = await confirmAction(
      context,
      title: l10n.groupsDeleteTitle(group.name),
      message: l10n.groupsDeleteMessage,
      confirmLabel: l10n.groupsDelete,
      destructive: true,
    );
    if (!ok) return;
    await ref.read(groupsProvider.notifier).deleteGroup(group.id);
  }
}

class _InviteCodeRow extends StatelessWidget {
  const _InviteCodeRow({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final code = group.displayInviteCode;
    final secondary = textTheme.bodySmall?.copyWith(
      color: palette.textSecondary,
    );
    if (code == null) return Text(l10n.groupsNoInviteCode, style: secondary);
    final expires = group.inviteCodeExpiresAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.groupsInviteCodeLabel, style: secondary),
        Row(
          children: [
            Flexible(
              child: SelectableText(
                code,
                style: textTheme.titleMedium?.copyWith(
                  color: palette.accent,
                  letterSpacing: 1.2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            AppIconButton(
              icon: Icons.copy_rounded,
              tooltip: l10n.groupsCopyCodeTooltip,
              color: palette.accent,
              onPressed: () =>
                  copyToClipboard(context, code, l10n.groupsInviteCodeCopied),
            ),
          ],
        ),
        Text(
          expires == null
              ? l10n.groupsInviteCodeApproval
              : l10n.groupsInviteCodeExpires(
                  DateHelpers.formatShortDate(expires),
                ),
          style: secondary,
        ),
      ],
    );
  }
}
