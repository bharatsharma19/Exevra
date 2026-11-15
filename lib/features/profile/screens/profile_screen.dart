import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/utils/haptics.dart';
import '../../../models/currency_info.dart';
import '../../../models/profile.dart';
import '../../../providers/app_lock_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../groups/widgets/groups_section.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameController = TextEditingController();
  final _avatarUrlController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _avatarUrlController.dispose();
    super.dispose();
  }

  void _showEditProfileDialog() {
    final profile = ref.read(userProfileProvider);
    if (profile == null) return;
    _nameController.text = profile.displayName;
    _avatarUrlController.text = profile.avatarUrl ?? '';
    String? fieldError;

    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Edit Profile'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameController,
                    maxLength: 60,
                    decoration: const InputDecoration(
                      labelText: 'Display Name',
                      prefixIcon: Icon(Icons.person_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _avatarUrlController,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'Profile Image URL (optional)',
                      prefixIcon: const Icon(Icons.link_rounded),
                      hintText: 'https://...',
                      errorText: fieldError,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final url = _avatarUrlController.text.trim();
                  final update = ProfileUpdate(
                    displayName: _nameController.text,
                    avatarUrl: url.isEmpty ? null : url,
                  );
                  final invalid = update.validate();
                  if (invalid != null) {
                    setDialogState(
                      () => fieldError = friendlyMessageForKey(invalid),
                    );
                    return;
                  }
                  Navigator.of(ctx).pop();
                  final failure = await ref
                      .read(profileProvider.notifier)
                      .updateProfile(update);
                  if (failure == null && mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text('Profile updated.'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setAppLock(bool enabled) async {
    AppHaptics.selection();
    final messenger = ScaffoldMessenger.of(context);
    final key = await ref.read(appLockProvider.notifier).setEnabled(enabled);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          key == null
              ? (enabled ? 'App Lock is on.' : 'App Lock is off.')
              : friendlyMessageForKey(key),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSignOutDialog() {
    AppHaptics.medium();
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sign out?'),
          content: const Text(
            'Your data stays in your account. To come back, sign in again '
            'with your email and password or Google. App Lock is turned off '
            'on this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                unawaited(ref.read(authControllerProvider.notifier).signOut());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog() {
    AppHaptics.heavy();
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(
            'Delete your account?',
            style: TextStyle(color: AppColors.error),
          ),
          content: const SingleChildScrollView(
            child: Text(
              'This permanently deletes your profile, your personal expenses, '
              'your settings and your AI assistant history.\n\n'
              'Expenses you added to shared groups stay with those groups so '
              "the other members' balances remain correct; they will show as "
              '"Former member". If you are a group admin, the longest-standing '
              'member becomes admin; groups with no other members are '
              'deleted. Payments still waiting for confirmation are '
              'cancelled.\n\n'
              "This can't be undone.",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                unawaited(_deleteAccount());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete account'),
            ),
          ],
        ),
      ),
    );
  }

  /// Deletes the account on the server behind a blocking progress dialog.
  /// The session ends only after the server confirmed the deletion; on
  /// failure nothing changes and the reason is shown.
  Future<void> _deleteAccount() async {
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Expanded(child: Text('Deleting your account...')),
              ],
            ),
          ),
        ),
      ),
    );
    final messenger = ScaffoldMessenger.of(context);
    final failure = await ref
        .read(authControllerProvider.notifier)
        .deleteAccount();
    if (navigator.mounted) navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failure == null
              ? 'Your account was deleted.'
              : friendlyMessage(failure),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final appLockState = ref.watch(appLockProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final profile = ref.watch(userProfileProvider);
    final themeMode = ref.watch(themePreferenceProvider);
    final resolvedDisplayName =
        (profile != null && profile.displayName.trim().isNotEmpty)
        ? profile.displayName
        : (authState.user?.userMetadata?['full_name'] as String? ??
              authState.user?.email?.split('@').first ??
              'User');
    return Scaffold(
      appBar: AppBar(title: const Text('Account & Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // User Profile Card
            GlassCard(
              borderRadius: 24,
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: AppColors.primaryCyan.withValues(
                      alpha: 0.2,
                    ),
                    child:
                        (profile?.avatarUrl != null &&
                            profile!.avatarUrl!.startsWith('https://'))
                        ? ClipOval(
                            child: Image.network(
                              profile.avatarUrl!,
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Text(
                                    (profile.displayName.isNotEmpty)
                                        ? profile.displayName[0].toUpperCase()
                                        : 'U',
                                    style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primaryCyan,
                                    ),
                                  ),
                            ),
                          )
                        : Text(
                            resolvedDisplayName.isNotEmpty
                                ? resolvedDisplayName[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primaryCyan,
                            ),
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                resolvedDisplayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: _showEditProfileDialog,
                              child: const Icon(
                                Icons.edit_outlined,
                                size: 16,
                                color: AppColors.primaryCyan,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          profile?.email ?? authState.user?.email ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? AppColors.darkTextTertiary
                                : AppColors.lightTextTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            const GroupsSection(),

            const SizedBox(height: 24),

            // App Settings Section
            Text(
              'Preferences & Environment',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 10),

            GlassCard(
              borderRadius: 20,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  // App Lock: turning it on or off needs authentication.
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(
                      Icons.fingerprint_rounded,
                      color: AppColors.primaryCyan,
                    ),
                    title: const Text(
                      'App Lock',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      appLockState.availability ==
                                  LockAvailability.unavailable &&
                              !appLockState.enabled
                          ? friendlyMessageForKey('lock_no_credentials')
                          : 'Ask for your fingerprint, face or device PIN '
                                'when opening Exevra',
                      style: const TextStyle(fontSize: 11),
                    ),
                    value: appLockState.enabled,
                    onChanged:
                        appLockState.isAuthenticating ||
                            (appLockState.availability ==
                                    LockAvailability.unavailable &&
                                !appLockState.enabled)
                        ? null
                        : (val) => unawaited(_setAppLock(val)),
                  ),
                  const Divider(height: 1),

                  // Currency Selector
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.monetization_on_outlined,
                      color: AppColors.primaryCyan,
                    ),
                    title: const Text(
                      'Default Currency',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: DropdownButton<String>(
                      value: ref.watch(preferredCurrencyProvider),
                      underline: const SizedBox(),
                      // Used for new personal expenses; groups keep their
                      // own currency.
                      onChanged: profile == null
                          ? null
                          : (val) {
                              if (val == null) return;
                              AppHaptics.selection();
                              unawaited(
                                ref
                                    .read(profileProvider.notifier)
                                    .setCurrency(val),
                              );
                            },
                      items: CurrencyInfo.all
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.code,
                              child: Text('${c.code} (${c.symbol})'),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const Divider(height: 1),

                  // Theme Mode Selector
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.dark_mode_outlined,
                      color: AppColors.primaryViolet,
                    ),
                    title: const Text(
                      'Theme Mode',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: DropdownButton<ThemePreference>(
                      value: themeMode,
                      underline: const SizedBox(),
                      onChanged: (val) {
                        if (val == null) return;
                        AppHaptics.selection();
                        unawaited(
                          ref.read(profileProvider.notifier).setThemeMode(val),
                        );
                      },
                      items: const [
                        DropdownMenuItem(
                          value: ThemePreference.system,
                          child: Text('System'),
                        ),
                        DropdownMenuItem(
                          value: ThemePreference.dark,
                          child: Text('Dark'),
                        ),
                        DropdownMenuItem(
                          value: ThemePreference.light,
                          child: Text('Light'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Haptics Toggle
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(
                      Icons.vibration_rounded,
                      color: AppColors.primaryEmerald,
                    ),
                    title: const Text(
                      'Tactile Haptic Feedback',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    value: profile?.hapticsEnabled ?? true,
                    activeThumbColor: AppColors.primaryEmerald,
                    onChanged: profile == null
                        ? null
                        : (val) {
                            AppHaptics.selection();
                            unawaited(
                              ref
                                  .read(profileProvider.notifier)
                                  .setHapticsEnabled(val),
                            );
                          },
                  ),
                  const Divider(height: 1),

                  // AI Consent Switch
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(
                      Icons.psychology_outlined,
                      color: AppColors.primaryRose,
                    ),
                    title: const Text(
                      'AI Spending Records Analysis',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Permit assistant to inject aggregate totals into prompt context',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: profile?.aiConsent ?? false,
                    activeThumbColor: AppColors.primaryRose,
                    onChanged: profile == null
                        ? null
                        : (val) {
                            AppHaptics.selection();
                            unawaited(
                              ref
                                  .read(profileProvider.notifier)
                                  .setAiConsent(val),
                            );
                          },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // App Store & Compliance Account Lifecycle Actions
            GlassCard(
              borderRadius: 20,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.logout_rounded,
                      color: Colors.orangeAccent,
                    ),
                    title: const Text(
                      'Sign Out',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: _showSignOutDialog,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.delete_forever_rounded,
                      color: AppColors.error,
                    ),
                    title: const Text(
                      'Delete Account',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.error,
                      ),
                    ),
                    onTap: _showDeleteAccountDialog,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
