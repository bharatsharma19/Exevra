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
import '../../../providers/failure_reporter.dart';
import '../../../providers/group_detail_providers.dart';
import '../../../providers/session_guard.dart';
import 'group_dialogs.dart';

/// A bordered row used for members, requests and invitations: [leading],
/// a title with a [subtitle] widget, and [actions] on the right.
class GroupRow extends StatelessWidget {
  /// Creates the row.
  const GroupRow({
    required this.leading,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.highlight = false,
    super.key,
  });

  /// Avatar or icon.
  final Widget leading;

  /// Main text.
  final String title;

  /// Status line under [title] (a badge, a date).
  final Widget? subtitle;

  /// Action buttons.
  final List<Widget> actions;

  /// Draws a stronger outline (a request waiting for the admin).
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceVariant.withValues(alpha: 0.5),
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: highlight ? palette.outlineStrong : palette.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              ExcludeSemantics(child: leading),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: MergeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(color: palette.textPrimary),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          subtitle!,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

/// A pending email invitation; the admin can revoke it.
class InvitationTile extends ConsumerWidget {
  const InvitationTile({
    required this.group,
    required this.invitation,
    super.key,
  });

  final Group group;
  final GroupInvitation invitation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final palette = context.palette;
    return GroupRow(
      leading: Icon(Icons.mail_outline_rounded, color: palette.accent),
      title: invitation.email,
      subtitle: Text(
        l10n.groupsInvitationStatus(
          invitation.role == GroupRole.viewer
              ? l10n.roleViewer
              : l10n.roleMember,
          DateHelpers.formatShortDate(invitation.expiresAt),
        ),
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
      ),
      actions: [
        AppIconButton(
          icon: Icons.cancel_outlined,
          tooltip: l10n.groupsRevokeTooltip,
          color: palette.danger,
          onPressed: () async {
            final ok = await confirmAction(
              context,
              title: l10n.groupsRevokeTitle,
              message: l10n.groupsRevokeMessage(invitation.email),
              confirmLabel: l10n.groupsRevokeAction,
              destructive: true,
            );
            if (!ok) return;
            final failure = await ref
                .read(pendingInvitationsProvider(group.id).notifier)
                .revoke(invitation.id);
            if (failure == null && context.mounted) {
              showMessage(context, l10n.groupsRevoked(invitation.email));
            }
          },
        ),
      ],
    );
  }
}

/// A pending code join: the admin approves (as member or viewer) or
/// denies it.
class JoinRequestTile extends ConsumerWidget {
  const JoinRequestTile({required this.group, required this.member, super.key});

  final Group group;
  final GroupMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final palette = context.palette;
    final notifier = ref.read(groupMembersProvider(group.id).notifier);
    return GroupRow(
      highlight: true,
      leading: AppAvatar(name: member.label, radius: 18),
      title: member.label,
      subtitle: StatusBadge(
        StatusBadgeKind.pending,
        label: l10n.groupsRequestPending,
      ),
      actions: [
        PopupMenuButton<GroupRole>(
          tooltip: l10n.groupsApproveTooltip(member.label),
          icon: Icon(Icons.check_circle_outline_rounded, color: palette.accent),
          onSelected: (role) async {
            final failure = await notifier.approve(member.userId, role: role);
            if (failure == null && context.mounted) {
              showMessage(
                context,
                role == GroupRole.viewer
                    ? l10n.groupsApprovedViewer(member.label)
                    : l10n.groupsApprovedMember(member.label),
                kind: AppSnackbarKind.success,
              );
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: GroupRole.member,
              child: Text(l10n.groupsApproveAsMember),
            ),
            PopupMenuItem(
              value: GroupRole.viewer,
              child: Text(l10n.groupsApproveAsViewer),
            ),
          ],
        ),
        AppIconButton(
          icon: Icons.block_rounded,
          tooltip: l10n.groupsDenyTooltip(member.label),
          color: palette.danger,
          onPressed: () async {
            final ok = await confirmAction(
              context,
              title: l10n.groupsDenyTitle(member.label),
              message: l10n.groupsDenyMessage,
              confirmLabel: l10n.groupsDenyAction,
              destructive: true,
            );
            if (!ok) return;
            await notifier.remove(member.userId);
          },
        ),
      ],
    );
  }
}

enum _MemberAction { makeMember, makeViewer, makeAdmin, remove }

/// An approved member with their role; the admin can change the role,
/// hand over admin or remove them, each after a confirmation where it
/// takes something away.
class MemberTile extends ConsumerWidget {
  const MemberTile({
    required this.group,
    required this.member,
    required this.isSelf,
    super.key,
  });

  final Group group;
  final GroupMember member;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final palette = context.palette;
    final canManage = group.isAdmin && !isSelf && !member.isAdmin;
    return GroupRow(
      leading: AppAvatar(name: member.label, radius: 18),
      title: isSelf ? l10n.groupsMemberYou(member.label) : member.label,
      subtitle: Align(
        alignment: AlignmentDirectional.centerStart,
        child: StatusBadge(
          member.isAdmin
              ? StatusBadgeKind.admin
              : member.isViewer
              ? StatusBadgeKind.viewer
              : StatusBadgeKind.member,
        ),
      ),
      actions: [
        if (canManage)
          PopupMenuButton<_MemberAction>(
            tooltip: l10n.groupsManageTooltip(member.label),
            icon: Icon(
              Icons.manage_accounts_outlined,
              color: palette.textSecondary,
            ),
            onSelected: (action) => unawaited(_act(context, ref, action)),
            itemBuilder: (_) => [
              if (member.isViewer)
                PopupMenuItem(
                  value: _MemberAction.makeMember,
                  child: Text(l10n.groupsMakeMember),
                )
              else
                PopupMenuItem(
                  value: _MemberAction.makeViewer,
                  child: Text(l10n.groupsMakeViewer),
                ),
              PopupMenuItem(
                value: _MemberAction.makeAdmin,
                child: Text(l10n.groupsMakeAdmin),
              ),
              PopupMenuItem(
                value: _MemberAction.remove,
                child: Text(
                  l10n.groupsRemoveMember,
                  style: TextStyle(color: palette.danger),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    _MemberAction action,
  ) async {
    final l10n = context.l10n;
    final notifier = ref.read(groupMembersProvider(group.id).notifier);
    final name = member.label;
    switch (action) {
      case _MemberAction.makeMember:
        final failure = await notifier.setRole(member.userId, GroupRole.member);
        if (failure == null && context.mounted) {
          showMessage(context, l10n.groupsApprovedMember(name));
        }
      case _MemberAction.makeViewer:
        final ok = await confirmAction(
          context,
          title: l10n.groupsMakeViewerTitle(name),
          message: l10n.groupsMakeViewerMessage(name),
          confirmLabel: l10n.groupsMakeViewerAction,
        );
        if (!ok) return;
        final failure = await notifier.setRole(member.userId, GroupRole.viewer);
        if (failure == null && context.mounted) {
          showMessage(context, l10n.groupsNowViewer(name));
        }
      case _MemberAction.makeAdmin:
        final ok = await confirmAction(
          context,
          title: l10n.groupsMakeAdminTitle(name),
          message: l10n.groupsMakeAdminMessage,
          confirmLabel: l10n.groupsMakeAdmin,
        );
        if (!ok) return;
        final failure = await notifier.transferAdmin(member.userId);
        if (failure == null && context.mounted) {
          showMessage(context, l10n.groupsNowAdmin(name));
        }
      case _MemberAction.remove:
        await _remove(context, ref);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final name = member.label;
    final ok = await confirmAction(
      context,
      title: l10n.groupsRemoveTitle(name),
      message: l10n.groupsRemoveMessage(group.name),
      confirmLabel: l10n.groupsRemoveAction,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final notifier = ref.read(groupMembersProvider(group.id).notifier);
    final failure = await notifier.remove(member.userId, report: false);
    if (failure == null) {
      if (context.mounted) showMessage(context, l10n.groupsRemoved(name));
      return;
    }
    if (!context.mounted || identical(failure, SessionGuard.dropped)) return;
    if (failure.key != 'outstanding_balance') {
      ref.read(failureReporterProvider.notifier).report(failure);
      return;
    }
    final force = await confirmAction(
      context,
      title: l10n.groupsNotSettledTitle(name),
      message: l10n.groupsNotSettledMessage,
      confirmLabel: l10n.groupsRemoveAnyway,
      destructive: true,
    );
    if (!force) return;
    final forced = await notifier.remove(member.userId, force: true);
    if (forced == null && context.mounted) {
      showMessage(context, l10n.groupsRemoved(name));
    }
  }
}
