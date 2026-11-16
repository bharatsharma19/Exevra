import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/auth_provider.dart';
import '../account_deletion.dart';

/// About, Sign out (after a confirmation) and Delete account.
class AccountSection extends ConsumerWidget {
  const AccountSection({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    AppHaptics.medium();
    final l10n = context.l10n;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.settingsSignOutTitle,
      message: l10n.settingsSignOutMessage,
      confirmLabel: l10n.settingsSignOut,
    );
    if (confirmed) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: l10n.settingsAccountSection),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            children: [
              AppListTile(
                key: const Key('profile-about'),
                leading: const Icon(Icons.info_outline),
                title: l10n.aboutTitle,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => unawaited(context.push(AppRoutes.profileAbout)),
              ),
              const Divider(height: 1),
              AppListTile(
                key: const Key('profile-sign-out'),
                leading: const Icon(Icons.logout_rounded),
                title: l10n.settingsSignOut,
                onTap: () => unawaited(_signOut(context, ref)),
              ),
              const Divider(height: 1),
              AppListTile(
                key: const Key('profile-delete-account'),
                leading: Icon(
                  Icons.delete_forever_outlined,
                  color: palette.danger,
                ),
                title: l10n.settingsDeleteAccount,
                subtitle: l10n.settingsDeleteAccountSubtitle,
                onTap: () => confirmAndDeleteAccount(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
