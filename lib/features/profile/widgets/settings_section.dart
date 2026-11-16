import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/currency_info.dart';
import '../../../models/profile.dart';
import '../../../providers/app_lock_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../chat/screens/ai_consent_screen.dart';
import 'currency_picker_sheet.dart';

/// Appearance, default currency, App Lock, vibration and the AI assistant.
///
/// Changes save at once; a failed save shows why in a snackbar (the switch
/// stays where the saved value is).
class SettingsSection extends ConsumerWidget {
  const SettingsSection({super.key});

  static void _report(BuildContext context, AppFailure? failure) {
    if (failure == null || !context.mounted) return;
    AppSnackbar.showError(
      context.l10n.settingsSaveFailed(friendlyMessage(failure)),
      messenger: ScaffoldMessenger.maybeOf(context),
    );
  }

  Future<void> _pickCurrency(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final code = await showCurrencyPicker(context, selected: current);
    if (code == null || code == current || !context.mounted) return;
    AppHaptics.selection();
    final failure = await ref.read(profileProvider.notifier).setCurrency(code);
    if (!context.mounted) return;
    if (failure == null) {
      AppSnackbar.showSuccess(
        context.l10n.settingsCurrencySaved(code),
        messenger: ScaffoldMessenger.maybeOf(context),
      );
    } else {
      _report(context, failure);
    }
  }

  Future<void> _setAppLock(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    AppHaptics.selection();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = context.l10n;
    final key = await ref.read(appLockProvider.notifier).setEnabled(enabled);
    if (key == null) {
      AppSnackbar.showSuccess(
        enabled ? l10n.settingsAppLockTurnedOn : l10n.settingsAppLockTurnedOff,
        messenger: messenger,
      );
    } else {
      AppSnackbar.showError(friendlyMessageForKey(key), messenger: messenger);
    }
  }

  /// On: the consent disclosure saves consent only after Allow. Off: at
  /// once (the chat history on this device is deleted with it).
  Future<void> _setAiConsent(
    BuildContext context,
    WidgetRef ref,
    bool on,
  ) async {
    AppHaptics.selection();
    if (on) {
      await AiConsentScreen.show(context);
      return;
    }
    final failure = await ref
        .read(profileProvider.notifier)
        .setAiConsent(false);
    if (context.mounted) _report(context, failure);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final profile = ref.watch(userProfileProvider);
    final lock = ref.watch(appLockProvider);
    final currency = CurrencyInfo.tryOf(ref.watch(preferredCurrencyProvider));
    final loaded = profile != null;
    final lockUnavailable =
        lock.availability == LockAvailability.unavailable && !lock.enabled;
    final aiOn = profile?.aiConsent ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: l10n.settingsSection),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _ThemeModeRow(),
              const Divider(height: 1),
              AppListTile(
                key: const Key('settings-currency'),
                leading: const Icon(Icons.payments_outlined),
                title: l10n.settingsCurrency,
                subtitle: currency == null
                    ? null
                    : l10n.settingsCurrencySubtitle(
                        currency.code,
                        currency.name,
                      ),
                subtitleMaxLines: 4,
                enabled: loaded,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: currency == null
                    ? null
                    : () =>
                          unawaited(_pickCurrency(context, ref, currency.code)),
              ),
              const Divider(height: 1),
              _SwitchRow(
                key: const Key('settings-app-lock'),
                icon: Icons.fingerprint_rounded,
                title: l10n.settingsAppLock,
                subtitle: lock.isAuthenticating
                    ? l10n.settingsAppLockChecking
                    : lockUnavailable
                    ? friendlyMessageForKey('lock_no_credentials')
                    : lock.enabled
                    ? l10n.settingsAppLockOn
                    : l10n.settingsAppLockOff,
                subtitleIcon: lockUnavailable ? Icons.info_outline : null,
                value: lock.enabled,
                onChanged: lock.isAuthenticating || lockUnavailable
                    ? null
                    : (on) => unawaited(_setAppLock(context, ref, on)),
              ),
              const Divider(height: 1),
              _SwitchRow(
                key: const Key('settings-haptics'),
                icon: Icons.vibration_rounded,
                title: l10n.settingsHaptics,
                subtitle: l10n.settingsHapticsSubtitle,
                value: profile?.hapticsEnabled ?? true,
                onChanged: !loaded
                    ? null
                    : (on) async {
                        AppHaptics.selection();
                        final failure = await ref
                            .read(profileProvider.notifier)
                            .setHapticsEnabled(on);
                        if (context.mounted) _report(context, failure);
                      },
              ),
              const Divider(height: 1),
              _SwitchRow(
                key: const Key('profile-ai-consent'),
                icon: Icons.auto_awesome_outlined,
                title: l10n.settingsAssistant,
                subtitle: aiOn
                    ? l10n.settingsAssistantOn
                    : l10n.settingsAssistantOff,
                value: aiOn,
                onChanged: !loaded
                    ? null
                    : (on) => unawaited(_setAiConsent(context, ref, on)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// System / Light / Dark as a segmented control (each segment has its own
/// icon and label, so the choice is not shown by colour alone).
class _ThemeModeRow extends ConsumerWidget {
  const _ThemeModeRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final palette = context.palette;
    final mode = ref.watch(themePreferenceProvider);
    final text = Theme.of(context).textTheme;
    final options = [
      (
        ThemePreference.system,
        Icons.brightness_auto_outlined,
        l10n.settingsThemeSystem,
      ),
      (
        ThemePreference.light,
        Icons.light_mode_outlined,
        l10n.settingsThemeLight,
      ),
      (ThemePreference.dark, Icons.dark_mode_outlined, l10n.settingsThemeDark),
    ];
    // Three segments do not fit side by side with large text; a list of
    // choices does.
    final compact =
        MediaQuery.textScalerOf(context).scale(1) >= AppListTile.largeTextScale;
    Future<void> select(ThemePreference value) async {
      if (value == mode) return;
      AppHaptics.selection();
      final failure = await ref
          .read(profileProvider.notifier)
          .setThemeMode(value);
      if (context.mounted) SettingsSection._report(context, failure);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.palette_outlined, color: palette.textSecondary),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Text(
                  l10n.settingsAppearance,
                  style: text.bodyLarge?.copyWith(color: palette.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (compact)
            for (final (value, icon, label) in options)
              AppListTile(
                key: Key('settings-theme-${value.name}'),
                leading: Icon(icon),
                title: label,
                selected: value == mode,
                semanticLabel: value == mode
                    ? '$label, ${l10n.settingsThemeSelected}'
                    : label,
                trailing: value == mode
                    ? Icon(Icons.check_rounded, color: palette.accent)
                    : null,
                onTap: () => unawaited(select(value)),
              )
          else
            SegmentedButton<ThemePreference>(
              key: const Key('settings-theme'),
              showSelectedIcon: false,
              segments: [
                for (final (value, icon, label) in options)
                  ButtonSegment(
                    value: value,
                    icon: Icon(icon),
                    label: Text(label),
                  ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) =>
                  unawaited(select(selection.single)),
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.settingsThemeHint,
            style: text.bodySmall?.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// A switch row whose subtitle explains the current state (or why it is
/// unavailable, with [subtitleIcon]).
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.subtitleIcon,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final IconData? subtitleIcon;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final subtitleStyle = TextStyle(color: palette.textSecondary);
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(title),
      subtitle: subtitleIcon == null
          ? Text(subtitle, style: subtitleStyle)
          : Text.rich(
              TextSpan(
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        end: AppSpacing.xs,
                      ),
                      child: Icon(
                        subtitleIcon,
                        size: AppSizes.iconSm,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                  TextSpan(text: subtitle),
                ],
              ),
              style: subtitleStyle,
            ),
      value: value,
      onChanged: onChanged,
    );
  }
}
