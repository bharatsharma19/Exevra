import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/errors/failure_messages.dart';
import '../../core/utils/haptics.dart';
import '../../providers/auth_provider.dart';

/// Asks the user to confirm and then deletes their account (Profile and
/// About share this flow).
///
/// The deletion runs behind a blocking progress dialog. The session ends
/// only after the server confirmed it; on failure nothing changes and the
/// reason is shown.
void confirmAndDeleteAccount(BuildContext context, WidgetRef ref) {
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
              unawaited(_deleteAccount(context, ref));
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

Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
  if (!context.mounted) return;
  final navigator = Navigator.of(context, rootNavigator: true);
  // Kept so only this dialog is closed: once the session ends, the
  // redirect to sign-in may already have removed it with the page below,
  // and a blind pop would remove the sign-in page instead.
  final progress = DialogRoute<void>(
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
  );
  unawaited(navigator.push(progress));
  final messenger = ScaffoldMessenger.of(context);
  final failure = await ref
      .read(authControllerProvider.notifier)
      .deleteAccount();
  if (navigator.mounted && progress.isActive) navigator.removeRoute(progress);
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
