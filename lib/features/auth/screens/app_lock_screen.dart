import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../providers/app_lock_provider.dart';
import '../../../providers/auth_provider.dart';

/// Covers the whole app while it is locked. It sits above the navigator
/// (so it cannot open dialogs) and the app below it is excluded from
/// semantics, focus and pointer input.
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
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final unavailable = lock.availability == LockAvailability.unavailable;
    final message = unavailable
        ? friendlyMessageForKey('lock_no_credentials')
        : lock.messageKey == null
        ? null
        : friendlyMessageForKey(lock.messageKey!);

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  excludeSemantics: true,
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(
                      Icons.lock_rounded,
                      size: 40,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '${AppConstants.appName} is locked',
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Use your fingerprint, face or device PIN to continue.',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (message != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      message,
                      style: text.bodyMedium?.copyWith(color: scheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                if (!unavailable)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: lock.isAuthenticating
                          ? null
                          : () => unawaited(
                              ref.read(appLockProvider.notifier).unlock(),
                            ),
                      icon: const Icon(Icons.fingerprint_rounded),
                      label: const Text('Unlock'),
                    ),
                  ),
                if (lock.canTurnOffWithoutDevice) ...[
                  const SizedBox(height: 12),
                  Text(
                    'You just signed in to your account, so you can turn App '
                    'Lock off on this device and turn it on again in Profile '
                    'once the device has a screen lock.',
                    style: text.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => unawaited(
                        ref
                            .read(appLockProvider.notifier)
                            .turnOffWithoutDevice(),
                      ),
                      child: const Text('Turn off App Lock'),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (_confirmSignOut) ...[
                  Text(
                    'Sign out on this device? App Lock stays on for this '
                    'account when you sign in again.',
                    style: text.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () =>
                            setState(() => _confirmSignOut = false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: () => unawaited(
                          ref.read(authControllerProvider.notifier).signOut(),
                        ),
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                ] else
                  SizedBox(
                    width: double.infinity,
                    child: unavailable && !lock.canTurnOffWithoutDevice
                        ? FilledButton(
                            onPressed: () =>
                                setState(() => _confirmSignOut = true),
                            child: const Text('Sign out'),
                          )
                        : TextButton(
                            onPressed: () =>
                                setState(() => _confirmSignOut = true),
                            child: const Text('Sign out instead'),
                          ),
                  ),
              ],
            ),
          ),
        ),
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
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Center(
        child: Icon(Icons.lock_rounded, size: 48, color: scheme.primary),
      ),
    );
  }
}
