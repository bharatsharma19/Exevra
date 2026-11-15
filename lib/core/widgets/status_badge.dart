import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// The statuses and roles a [StatusBadge] can show.
enum StatusBadgeKind {
  /// Settlement waiting for the payee to confirm.
  pending,

  /// Settlement confirmed by the payee.
  confirmed,

  /// Settlement voided.
  voided,

  /// Group administrator.
  admin,

  /// Group member.
  member,

  /// Read-only group member.
  viewer,
}

/// A small pill showing a status or role with an icon **and** text, so the
/// meaning never depends on colour alone. Colours are container pairs that
/// pass 4.5:1 in both themes.
class StatusBadge extends StatelessWidget {
  /// Creates a badge.
  const StatusBadge(this.kind, {this.label, super.key});

  /// What the badge shows.
  final StatusBadgeKind kind;

  /// Overrides the default localized text.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = context.l10n;
    final (
      Color background,
      Color foreground,
      IconData icon,
      String text,
    ) = switch (kind) {
      StatusBadgeKind.pending => (
        palette.warningContainer,
        palette.onWarningContainer,
        Icons.schedule,
        l10n.statusPending,
      ),
      StatusBadgeKind.confirmed => (
        palette.successContainer,
        palette.onSuccessContainer,
        Icons.check_circle_outline,
        l10n.statusConfirmed,
      ),
      StatusBadgeKind.voided => (
        palette.surfaceVariant,
        palette.textSecondary,
        Icons.block,
        l10n.statusVoided,
      ),
      StatusBadgeKind.admin => (
        palette.accentContainer,
        palette.onAccentContainer,
        Icons.shield_outlined,
        l10n.roleAdmin,
      ),
      StatusBadgeKind.member => (
        palette.secondaryContainer,
        palette.onSecondaryContainer,
        Icons.person_outline,
        l10n.roleMember,
      ),
      StatusBadgeKind.viewer => (
        palette.surfaceVariant,
        palette.textSecondary,
        Icons.visibility_outlined,
        l10n.roleViewer,
      ),
    };
    final style = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: foreground);
    return Semantics(
      label: label ?? text,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadius.pillAll,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  label ?? text,
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
