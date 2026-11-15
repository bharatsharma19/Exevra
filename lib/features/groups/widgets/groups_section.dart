import 'dart:async';

import 'package:flutter/material.dart';
import '../../../providers/session_guard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_helpers.dart';
import '../../../models/group.dart';
import '../../../models/invitation.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/failure_reporter.dart';
import '../../../providers/group_detail_providers.dart';
import '../../../providers/groups_provider.dart';
import '../../shared/failure_retry.dart';
import 'group_dialogs.dart';
import 'settlements_card.dart';

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
        Text(
          'Groups',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        const MyGroupsCard(),
        if (group != null) ...[
          const SizedBox(height: 14),
          ActiveGroupCard(group: group),
          const SizedBox(height: 18),
          SettlementsCard(group: group),
        ],
      ],
    );
  }
}

TextStyle _sectionStyle(BuildContext context) => TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w700,
  color: Theme.of(context).colorScheme.onSurfaceVariant,
);

/// Personal mode, the user's groups (pending requests marked), create
/// and join.
class MyGroupsCard extends ConsumerWidget {
  const MyGroupsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final groupsAsync = ref.watch(groupsProvider);
    // Only the signed-in user's groups, never a previous user's.
    final groups = ref.watch(currentGroupsProvider)?.groups ?? const <Group>[];
    final active = ref.watch(activeGroupProvider);
    final notifier = ref.read(groupsProvider.notifier);

    return GlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.domain_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'My groups (${groups.length})',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Create group',
                icon: Icon(
                  Icons.add_circle_outline_rounded,
                  size: 22,
                  color: scheme.primary,
                ),
                onPressed: () => unawaited(showCreateGroupDialog(context, ref)),
              ),
              IconButton(
                tooltip: 'Join with code',
                icon: Icon(
                  Icons.group_add_rounded,
                  size: 22,
                  color: scheme.secondary,
                ),
                onPressed: () => unawaited(showJoinGroupDialog(context, ref)),
              ),
            ],
          ),
          if (groupsAsync.hasError && !groupsAsync.isLoading)
            FailureRetry(
              error: groupsAsync.error!,
              compact: true,
              onRetry: () => ref.read(groupsProvider.notifier).retry(),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Personal (no group)'),
                selected: active == null,
                onSelected: (_) => unawaited(notifier.switchScope(null)),
              ),
              for (final g in groups)
                ChoiceChip(
                  // A pending request opens once an admin approves.
                  label: Text(
                    g.isPending ? '${g.name} (waiting for approval)' : g.name,
                  ),
                  selected: active?.id == g.id,
                  avatar: Icon(
                    g.isPending
                        ? Icons.hourglass_top_rounded
                        : Icons.groups_rounded,
                    size: 16,
                  ),
                  onSelected: g.isPending
                      ? null
                      : (_) => unawaited(notifier.switchScope(g.id)),
                ),
            ],
          ),
          if (groups.any((g) => g.isPending)) ...[
            const SizedBox(height: 8),
            Text(
              'Groups waiting for approval open once their admin approves '
              'you.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// The active group: invite code and invitations (admin), join requests,
/// members and roles, leave and delete.
class ActiveGroupCard extends ConsumerWidget {
  const ActiveGroupCard({super.key, required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
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

    return GlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  group.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _RoleBadge(
                label: group.isAdmin
                    ? 'ADMIN'
                    : group.isViewer
                    ? 'VIEWER'
                    : 'MEMBER',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Currency ${group.currency} • ${group.membersCount} '
            '${group.membersCount == 1 ? 'member' : 'members'}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if (group.isViewer) ...[
            const SizedBox(height: 8),
            Text(
              'You can see this group but not add expenses. Ask the admin to '
              'make you a member.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
          if (group.isAdmin) ...[
            const SizedBox(height: 12),
            _InviteCodeRow(group: group),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        unawaited(showInviteByEmailDialog(context, ref, group)),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                    label: const Text('Invite by email'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => unawaited(_rotateCode(context, ref)),
                    icon: const Icon(Icons.autorenew_rounded, size: 16),
                    label: const Text('New code'),
                  ),
                ),
              ],
            ),
          ],
          if (invitations.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'Pending invitations (${invitations.length})',
              style: _sectionStyle(context),
            ),
            const SizedBox(height: 8),
            for (final inv in invitations)
              _InvitationTile(group: group, invitation: inv),
          ],
          if (membersAsync.hasError && members.isEmpty) ...[
            const SizedBox(height: 12),
            FailureRetry(
              error: membersAsync.error!,
              compact: true,
              onRetry: () => ref.invalidate(groupMembersProvider(group.id)),
            ),
          ] else if (membersAsync.isLoading && members.isEmpty) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (group.isAdmin && requests.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'Waiting for approval (${requests.length})',
              style: _sectionStyle(context),
            ),
            const SizedBox(height: 8),
            for (final m in requests) _JoinRequestTile(group: group, member: m),
          ],
          if (approved.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('Members (${approved.length})', style: _sectionStyle(context)),
            const SizedBox(height: 8),
            for (final m in approved)
              _MemberTile(group: group, member: m, isSelf: m.userId == userId),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => unawaited(_leave(context, ref, approved)),
                icon: const Icon(Icons.exit_to_app_rounded, size: 16),
                label: const Text('Leave group'),
              ),
              if (group.isAdmin)
                TextButton.icon(
                  onPressed: () =>
                      unawaited(_delete(context, ref, approved.length)),
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('Delete group'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _rotateCode(BuildContext context, WidgetRef ref) async {
    final ok = await confirmAction(
      context,
      title: 'Issue a new invite code?',
      message:
          'The current code stops working. People who have it can no longer '
          'ask to join.',
      confirmLabel: 'New code',
    );
    if (!ok || !context.mounted) return;
    final (code, failure) = await ref
        .read(groupsProvider.notifier)
        .rotateInviteCode(group.id);
    if (code == null || failure != null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('New invite code: ${code.display}'),
        action: SnackBarAction(
          label: 'Share',
          onPressed: () =>
              unawaited(shareInviteCode(context, ref, group, code.display)),
        ),
      ),
    );
  }

  Future<void> _leave(
    BuildContext context,
    WidgetRef ref,
    List<GroupMember> approved,
  ) async {
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
          ? "You're the only member, so leaving deletes ${group.name} and "
                'all its expenses and payments.'
          : "You're the admin. ${others.first.label}, the longest-standing "
                'member, becomes the admin when you leave. You can choose '
                'someone else first with "Make admin".\n\nYou need to be '
                'settled up to leave.';
    } else {
      message =
          "You'll no longer see ${group.name}'s expenses and balances. Your "
          'past expenses stay in the group.\n\nYou need to be settled up to '
          'leave.';
    }
    final ok = await confirmAction(
      context,
      title: 'Leave ${group.name}?',
      message: message,
      confirmLabel: 'Leave group',
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
    if (approvedCount > 1) {
      showMessage(
        context,
        'Remove the other members or make someone else admin before deleting '
        'this group.',
      );
      return;
    }
    final ok = await confirmAction(
      context,
      title: 'Delete ${group.name}?',
      message:
          'This permanently deletes the group with all its expenses and '
          'payments. It cannot be undone.',
      confirmLabel: 'Delete group',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(groupsProvider.notifier).deleteGroup(group.id);
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.primary),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: scheme.primary,
        ),
      ),
    );
  }
}

class _InviteCodeRow extends StatelessWidget {
  const _InviteCodeRow({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final code = group.displayInviteCode;
    if (code == null) {
      return Text(
        'No invite code yet. Tap New code to create one.',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      );
    }
    final expires = group.inviteCodeExpiresAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Invite code ',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            Flexible(
              child: SelectableText(
                code,
                maxLines: 1,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: scheme.primary,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Copy invite code',
              icon: Icon(Icons.copy_rounded, size: 16, color: scheme.primary),
              onPressed: () =>
                  copyToClipboard(context, code, 'Invite code copied.'),
            ),
          ],
        ),
        Text(
          expires == null
              ? 'People who join with the code wait for your approval.'
              : 'Expires ${DateHelpers.formatShortDate(expires)}. People who '
                    'join with it wait for your approval.',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

BoxDecoration _tileDecoration(BuildContext context, {Color? border}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(12),
    color: isDark
        ? AppColors.darkCardElevated.withValues(alpha: 0.5)
        : AppColors.lightCardElevated,
    border: Border.all(
      color: border ?? (isDark ? AppColors.darkBorder : AppColors.lightBorder),
    ),
  );
}

class _InvitationTile extends ConsumerWidget {
  const _InvitationTile({required this.group, required this.invitation});

  final Group group;
  final GroupInvitation invitation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: _tileDecoration(context),
      child: Row(
        children: [
          Icon(Icons.mail_outline_rounded, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invitation.email,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${invitation.role == GroupRole.viewer ? 'Viewer' : 'Member'}'
                  ' • expires '
                  '${DateHelpers.formatShortDate(invitation.expiresAt)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Revoke invitation',
            icon: Icon(Icons.cancel_outlined, size: 18, color: scheme.error),
            onPressed: () async {
              final ok = await confirmAction(
                context,
                title: 'Revoke this invitation?',
                message: 'The link sent to ${invitation.email} stops working.',
                confirmLabel: 'Revoke',
                destructive: true,
              );
              if (!ok) return;
              await ref
                  .read(pendingInvitationsProvider(group.id).notifier)
                  .revoke(invitation.id);
            },
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.member);

  final GroupMember member;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = member.label;
    return CircleAvatar(
      radius: 16,
      backgroundColor: scheme.primary.withValues(alpha: 0.15),
      child: Text(
        label.isEmpty ? '?' : label.characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: scheme.primary,
        ),
      ),
    );
  }
}

/// A pending code join: the admin approves (as member or viewer) or
/// denies it.
class _JoinRequestTile extends ConsumerWidget {
  const _JoinRequestTile({required this.group, required this.member});

  final Group group;
  final GroupMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(groupMembersProvider(group.id).notifier);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: _tileDecoration(
        context,
        border: AppColors.warning.withValues(alpha: 0.4),
      ),
      child: Row(
        children: [
          _Avatar(member),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              member.label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          PopupMenuButton<GroupRole>(
            tooltip: 'Approve ${member.label}',
            icon: const Icon(Icons.check_circle_outline_rounded),
            onSelected: (role) async {
              final failure = await notifier.approve(member.userId, role: role);
              if (failure == null && context.mounted) {
                showMessage(
                  context,
                  role == GroupRole.viewer
                      ? '${member.label} can now see the group.'
                      : '${member.label} can now add expenses.',
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: GroupRole.member,
                child: Text('Approve as member'),
              ),
              PopupMenuItem(
                value: GroupRole.viewer,
                child: Text('Approve as viewer (read only)'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Deny ${member.label}',
            icon: Icon(
              Icons.block_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              final ok = await confirmAction(
                context,
                title: 'Deny ${member.label}?',
                message:
                    "They won't join the group and can't ask again with "
                    'this code. You can still invite them by email later.',
                confirmLabel: 'Deny',
                destructive: true,
              );
              if (!ok) return;
              await notifier.remove(member.userId);
            },
          ),
        ],
      ),
    );
  }
}

enum _MemberAction { makeMember, makeViewer, makeAdmin, remove }

/// An approved member; the admin can change the role, hand over admin or
/// remove them.
class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.group,
    required this.member,
    required this.isSelf,
  });

  final Group group;
  final GroupMember member;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final roleLabel = member.isAdmin
        ? 'Admin'
        : member.isViewer
        ? 'Viewer (read only)'
        : 'Member (can add)';
    final canManage = group.isAdmin && !isSelf && !member.isAdmin;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: _tileDecoration(context),
      child: Row(
        children: [
          _Avatar(member),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSelf ? '${member.label} (you)' : member.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  roleLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: member.isAdmin
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (canManage)
            PopupMenuButton<_MemberAction>(
              tooltip: 'Manage ${member.label}',
              icon: const Icon(Icons.manage_accounts_outlined, size: 20),
              onSelected: (action) => unawaited(_act(context, ref, action)),
              itemBuilder: (_) => [
                if (member.isViewer)
                  const PopupMenuItem(
                    value: _MemberAction.makeMember,
                    child: Text('Make member (can add expenses)'),
                  )
                else
                  const PopupMenuItem(
                    value: _MemberAction.makeViewer,
                    child: Text('Make viewer (read only)'),
                  ),
                const PopupMenuItem(
                  value: _MemberAction.makeAdmin,
                  child: Text('Make admin'),
                ),
                PopupMenuItem(
                  value: _MemberAction.remove,
                  child: Text(
                    'Remove from group',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    _MemberAction action,
  ) async {
    final notifier = ref.read(groupMembersProvider(group.id).notifier);
    switch (action) {
      case _MemberAction.makeMember:
        final failure = await notifier.setRole(member.userId, GroupRole.member);
        if (failure == null && context.mounted) {
          showMessage(context, '${member.label} can now add expenses.');
        }
      case _MemberAction.makeViewer:
        final failure = await notifier.setRole(member.userId, GroupRole.viewer);
        if (failure == null && context.mounted) {
          showMessage(context, '${member.label} can now only view the group.');
        }
      case _MemberAction.makeAdmin:
        final ok = await confirmAction(
          context,
          title: 'Make ${member.label} the admin?',
          message:
              'A group has one admin. You become a member, and your pending '
              'email invitations are cancelled.',
          confirmLabel: 'Make admin',
        );
        if (!ok) return;
        final failure = await notifier.transferAdmin(member.userId);
        if (failure == null && context.mounted) {
          showMessage(context, '${member.label} is now the admin.');
        }
      case _MemberAction.remove:
        await _remove(context, ref);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final ok = await confirmAction(
      context,
      title: 'Remove ${member.label}?',
      message:
          "They lose access to ${group.name} and can't rejoin with the invite "
          'code. Their past expenses stay in the group.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final notifier = ref.read(groupMembersProvider(group.id).notifier);
    final failure = await notifier.remove(member.userId, report: false);
    if (failure == null) {
      if (context.mounted) {
        showMessage(context, '${member.label} was removed from the group.');
      }
      return;
    }
    if (!context.mounted || identical(failure, SessionGuard.dropped)) return;
    if (failure.key != 'outstanding_balance') {
      ref.read(failureReporterProvider.notifier).report(failure);
      return;
    }
    final force = await confirmAction(
      context,
      title: '${member.label} is not settled up',
      message:
          'They still have an open balance or a payment waiting for '
          'confirmation. If you remove them anyway, their balance stays in '
          "the group's balances but can't be settled in the app.",
      confirmLabel: 'Remove anyway',
      destructive: true,
    );
    if (!force) return;
    final forced = await notifier.remove(member.userId, force: true);
    if (forced == null && context.mounted) {
      showMessage(context, '${member.label} was removed from the group.');
    }
  }
}
