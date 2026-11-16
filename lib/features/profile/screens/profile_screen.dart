import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/groups_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../groups/widgets/groups_section.dart';
import '../widgets/account_section.dart';
import '../widgets/edit_profile_dialog.dart';
import '../widgets/profile_header_card.dart';
import '../widgets/settings_section.dart';

/// The Profile tab: who is signed in, their groups, the settings and the
/// account actions. Pull down to reload the profile and the groups.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(profileProvider)
      ..invalidate(groupsProvider);
    // Keeps the indicator up until the profile is back (or failed).
    try {
      await ref.read(profileProvider.notifier).loaded;
    } on Object {
      // Shown by the error state below.
    }
  }

  Future<void> _editProfile(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(userProfileProvider);
    if (profile == null) return;
    final saved = await showEditProfileDialog(
      context,
      name: profile.displayName,
      avatarUrl: profile.avatarUrl,
      onSave: ref.read(profileProvider.notifier).updateProfile,
    );
    if (saved && context.mounted) {
      AppSnackbar.showSuccess(
        context.l10n.profileSaved,
        messenger: ScaffoldMessenger.maybeOf(context),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final user = ref.watch(authControllerProvider.select((s) => s.user));
    final profile = ref.watch(userProfileProvider);
    final load = ref.watch(profileProvider);
    final name = profile != null && profile.displayName.trim().isNotEmpty
        ? profile.displayName
        : (user?.userMetadata?['full_name'] as String? ??
              user?.email?.split('@').first ??
              l10n.profileFallbackName);

    final Widget header;
    if (profile == null && load.isLoading) {
      header = const _HeaderSkeleton();
    } else if (profile == null && load.hasError) {
      final error = load.error;
      header = AppCard(
        key: const Key('profile-load-failed'),
        child: ErrorState(
          title: l10n.profileLoadFailed,
          message: friendlyMessage(
            error is AppFailure ? error : const AppFailure.unknown(),
          ),
          onRetry: () {
            ref.invalidate(profileProvider);
            // The groups need the profile, so they failed with it.
            if (ref.read(groupsProvider).hasError) {
              ref.invalidate(groupsProvider);
            }
          },
        ),
      );
    } else {
      header = ProfileHeaderCard(
        name: name,
        email: profile?.email ?? user?.email ?? '',
        avatarUrl: profile?.avatarUrl,
        onEdit: profile == null
            ? null
            : () => unawaited(_editProfile(context, ref)),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          // A few sections: built at once (not lazily), so every row is
          // reachable by focus traversal and tests.
          child: SingleChildScrollView(
            key: const Key('profile-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.sm,
              AppSpacing.gutter,
              AppSpacing.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: AppSpacing.xl),
                const GroupsSection(),
                const SizedBox(height: AppSpacing.xl),
                const SettingsSection(),
                const SizedBox(height: AppSpacing.xl),
                const AccountSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder of the header card while the profile loads.
class _HeaderSkeleton extends StatelessWidget {
  const _HeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.loading,
      child: const AppCard(
        key: Key('profile-loading'),
        child: Row(
          children: [
            SkeletonBox.circle(size: 64),
            SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 160, height: 20),
                  SizedBox(height: AppSpacing.sm),
                  SkeletonBox(width: 200, height: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
