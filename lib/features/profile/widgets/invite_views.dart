import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/group.dart';
import '../../../models/invitation.dart';

/// What the invite screen is doing right now.
enum InviteBusy { none, accepting, declining }

/// Placeholder while the invitation loads.
class InviteLoadingView extends StatelessWidget {
  const InviteLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.inviteLoading,
      liveRegion: true,
      child: const Column(
        key: Key('invite-loading'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: SkeletonBox.circle(size: 80)),
          SizedBox(height: AppSpacing.xl),
          Center(child: SkeletonBox(width: 220, height: 24)),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 16),
          SizedBox(height: AppSpacing.xl),
          SkeletonBox(height: 140),
        ],
      ),
    );
  }
}

/// Icon, title and message at the top of every invite state. The title
/// is a header and the message is announced when the state changes.
class InviteHero extends StatelessWidget {
  const InviteHero({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.tone = InviteTone.accent,
  });

  final IconData icon;
  final String title;
  final String message;
  final InviteTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final (background, foreground) = switch (tone) {
      InviteTone.accent => (palette.accentContainer, palette.onAccentContainer),
      InviteTone.success => (
        palette.successContainer,
        palette.onSuccessContainer,
      ),
      InviteTone.warning => (
        palette.warningContainer,
        palette.onWarningContainer,
      ),
      InviteTone.danger => (palette.dangerContainer, palette.onDangerContainer),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: StateIcon(
            icon: icon,
            background: background,
            foreground: foreground,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: palette.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          liveRegion: true,
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: palette.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Colour pair of the [InviteHero] icon (the title says the same).
enum InviteTone { accent, success, warning, danger }

/// Group, inviter, role and the expiry date of an invitation.
class InviteDetailsCard extends StatelessWidget {
  const InviteDetailsCard({
    super.key,
    required this.details,
    required this.inviterName,
    required this.isExpired,
  });

  final InvitationDetails details;
  final String inviterName;
  final bool isExpired;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final expires = DateFormat.yMMMd(
      locale,
    ).format(details.expiresAt.toLocal());
    final roleKind = switch (details.role) {
      GroupRole.admin => StatusBadgeKind.admin,
      GroupRole.member => StatusBadgeKind.member,
      GroupRole.viewer => StatusBadgeKind.viewer,
    };
    return AppCard(
      key: const Key('invite-details'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyValueRow(label: l10n.inviteGroupLabel, value: details.groupName),
          KeyValueRow(label: l10n.inviteInvitedBy, value: inviterName),
          KeyValueRow.custom(
            label: l10n.inviteRoleLabel,
            valueWidget: StatusBadge(roleKind),
          ),
          KeyValueRow(
            label: isExpired ? l10n.inviteExpiredOn : l10n.inviteValidUntil,
            value: expires,
          ),
        ],
      ),
    );
  }
}
