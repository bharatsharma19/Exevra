import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../core/utils/app_clock.dart';

/// Greeting, the user's name and the button that switches between the
/// personal view and a group.
///
/// The parts are stacked, so a long name or group name never squeezes the
/// other at narrow widths or large text sizes.
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    required this.displayName,
    required this.scopeName,
    required this.inGroup,
    required this.onChangeScope,
    this.now,
    super.key,
  });

  final String displayName;

  /// "Personal" or the active group's name.
  final String scopeName;
  final bool inGroup;
  final VoidCallback onChangeScope;

  /// Clock used for the greeting (tests).
  final DateTime? now;

  static String greeting(AppLocalizations l10n, DateTime time) {
    if (time.hour < 12) return l10n.dashboardGreetingMorning;
    if (time.hour < 17) return l10n.dashboardGreetingAfternoon;
    return l10n.dashboardGreetingEvening;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting(l10n, now ?? AppClock.now()),
                style: textTheme.bodyMedium?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
              Text(
                displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.headlineSmall?.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Tooltip(
          message: l10n.dashboardScopeButtonTooltip,
          excludeFromSemantics: true,
          child: Semantics(
            label: l10n.dashboardScopeButtonLabel(scopeName),
            button: true,
            excludeSemantics: true,
            onTap: onChangeScope,
            child: OutlinedButton.icon(
              key: const Key('dashboard-scope-button'),
              onPressed: onChangeScope,
              icon: Icon(
                inGroup ? Icons.groups_rounded : Icons.person_rounded,
                size: AppSizes.iconSm,
              ),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      scopeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down_rounded),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
