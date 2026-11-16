import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure_messages.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/app_lock_provider.dart';
import '../../../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';

/// Covers the whole app while it is locked. It sits above the navigator
/// (so it cannot open dialogs; the sign-out confirmation is inline) and the
/// app below it is excluded from semantics, focus and pointer input.
///
/// The main action is Unlock (fingerprint, face or device PIN). A device
/// without a screen lock gets an explanation instead, plus Turn off App
/// Lock right after a fresh sign-in; Sign out is always the way out.
class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  bool _confirmSignOut = false;

  @override
  void initState() {
    super.initState();
    // Prompt once when the lock appears; Unlock retries.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final lock = ref.read(appLockProvider);
      if (lock.availability != LockAvailability.unavailable) {
        unawaited(ref.read(appLockProvider.notifier).unlock());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final palette = context.palette;
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final unavailable = lock.availability == LockAvailability.unavailable;
    final message = unavailable
        ? friendlyMessageForKey('lock_no_credentials')
        : lock.messageKey == null
        ? null
        : friendlyMessageForKey(lock.messageKey!);

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: StateIcon(
                      icon: Icons.lock_rounded,
                      background: palette.accentContainer,
                      foreground: palette.onAccentContainer,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.lockTitle,
                      style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: palette.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.lockMessage,
                    style: text.bodyMedium?.copyWith(
                      color: palette.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (message != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    AuthMessage(message, isError: !unavailable),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  if (!unavailable) ...[
                    LoadingButton(
                      key: const Key('lock-unlock'),
                      label: l10n.lockUnlock,
                      icon: Icons.fingerprint_rounded,
                      isLoading: lock.isAuthenticating,
                      onPressed: () => unawaited(
                        ref.read(appLockProvider.notifier).unlock(),
                      ),
                    ),
                    if (lock.isAuthenticating) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          l10n.lockChecking,
                          textAlign: TextAlign.center,
                          style: text.bodySmall?.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                  if (lock.canTurnOffWithoutDevice) ...[
                    Text(
                      l10n.lockTurnOffExplanation,
                      style: text.bodyMedium?.copyWith(
                        color: palette.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    LoadingButton(
                      key: const Key('lock-turn-off'),
                      label: l10n.lockTurnOff,
                      onPressed: () => unawaited(
                        ref
                            .read(appLockProvider.notifier)
                            .turnOffWithoutDevice(),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  if (_confirmSignOut)
                    _SignOutConfirm(
                      onCancel: () => setState(() => _confirmSignOut = false),
                      onConfirm: () => unawaited(
                        ref.read(authControllerProvider.notifier).signOut(),
                      ),
                    )
                  else if (unavailable && !lock.canTurnOffWithoutDevice)
                    LoadingButton(
                      key: const Key('lock-sign-out'),
                      label: l10n.lockSignOut,
                      icon: Icons.logout_rounded,
                      onPressed: () => setState(() => _confirmSignOut = true),
                    )
                  else
                    TextButton.icon(
                      key: const Key('lock-sign-out'),
                      onPressed: () => setState(() => _confirmSignOut = true),
                      icon: const Icon(Icons.logout_rounded),
                      label: Text(l10n.lockSignOutInstead),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The inline "Sign out on this device?" question (the lock screen cannot
/// open a dialog). Announced when it appears.
class _SignOutConfirm extends StatelessWidget {
  const _SignOutConfirm({required this.onCancel, required this.onConfirm});

  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.lockSignOutConfirm,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textPrimary),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              TextButton(onPressed: onCancel, child: Text(l10n.cancel)),
              LoadingButton(
                key: const Key('lock-sign-out-confirm'),
                label: l10n.lockSignOut,
                variant: LoadingButtonVariant.destructive,
                expand: false,
                onPressed: onConfirm,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown over the app while it is inactive, so the app switcher preview
/// shows no financial data.
class PrivacyCover extends StatelessWidget {
  const PrivacyCover({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: context.l10n.lockCoverLabel,
      child: ColoredBox(
        color: palette.background,
        child: Center(
          child: Icon(
            Icons.lock_rounded,
            size: AppSizes.iconLg,
            color: palette.accent,
          ),
        ),
      ),
    );
  }
}
