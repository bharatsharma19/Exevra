import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/errors/app_failure.dart';
import '../../core/errors/failure_messages.dart';
import '../../core/utils/haptics.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';

/// Asks the user to confirm and then deletes their account (Profile and
/// About share this flow).
///
/// The deletion runs behind a blocking progress dialog. The session ends
/// only after the server confirmed it; on failure nothing changes and the
/// reason is shown. When the server wants a recent sign-in, the user signs
/// in again (password, Google or Apple) and the deletion runs once more.
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
  final auth = ref.read(authControllerProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  var failure = await _withProgress(
    context,
    'Deleting your account...',
    auth.deleteAccount,
  );
  // The server wants a sign-in from the last few minutes: confirm it is
  // the user, then try once more.
  if (failure?.key == 'reauth_required' && context.mounted) {
    failure = await _reauthenticate(context, auth);
    if (failure == null && context.mounted) {
      failure = await _withProgress(
        context,
        'Deleting your account...',
        auth.deleteAccount,
      );
    }
  }
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

/// Asks the user to sign in again (password, Google or Apple). Returns the
/// failure, or null once the session is fresh.
Future<AppFailure?> _reauthenticate(
  BuildContext context,
  AuthController auth,
) async {
  final method = auth.reauthMethod;
  if (method == null) return const AppFailure.business('reauth_required');
  const cancelled = AppFailure.business('reauth_cancelled');
  String? password;
  if (method == ReauthMethod.password) {
    password = await showDialog<String>(
      context: context,
      builder: (_) => const _PasswordDialog(),
    );
    if (password == null) return cancelled;
  } else {
    final provider = method == ReauthMethod.google ? 'Google' : 'Apple';
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm it's you"),
        content: Text(
          'For your security, sign in with $provider again to delete your '
          'account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('reauth-continue'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Continue with $provider'),
          ),
        ],
      ),
    );
    if (go != true) return cancelled;
  }
  if (!context.mounted) return cancelled;
  return _withProgress(
    context,
    "Checking it's you...",
    () => auth.reauthenticate(password: password),
  );
}

/// Runs [action] behind a blocking progress dialog showing [label].
Future<AppFailure?> _withProgress(
  BuildContext context,
  String label,
  Future<AppFailure?> Function() action,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  // Kept so only this dialog is closed: once the session ends, the
  // redirect to sign-in may already have removed it with the page below,
  // and a blind pop would remove the sign-in page instead.
  final progress = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    ),
  );
  unawaited(navigator.push(progress));
  final failure = await action();
  if (navigator.mounted && progress.isActive) navigator.removeRoute(progress);
  return failure;
}

/// Asks for the account password; pops it, or null on Cancel.
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _controller.text;
    if (password.isEmpty) return;
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text("Confirm it's you"),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'For your security, enter your password to delete your account.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('reauth-password'),
            controller: _controller,
            autofocus: true,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      ElevatedButton(
        key: const Key('reauth-continue'),
        onPressed: _submit,
        child: const Text('Continue'),
      ),
    ],
  );
}
