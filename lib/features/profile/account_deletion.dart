import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/errors/failure_messages.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/ui/root_messenger.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/widgets.dart';
import '../../l10n/l10n.dart';
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
  final l10n = context.l10n;
  unawaited(() async {
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.settingsDeleteTitle,
      message: l10n.settingsDeleteMessage,
      confirmLabel: l10n.settingsDeleteAccount,
      destructive: true,
    );
    if (confirmed && context.mounted) await _deleteAccount(context, ref);
  }());
}

Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
  if (!context.mounted) return;
  final auth = ref.read(authControllerProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  var failure = await _withProgress(
    context,
    l10n.settingsDeleting,
    auth.deleteAccount,
  );
  // The server wants a sign-in from the last few minutes: confirm it is
  // the user, then try once more.
  if (failure?.key == 'reauth_required' && context.mounted) {
    failure = await _reauthenticate(context, auth);
    if (failure == null && context.mounted) {
      failure = await _withProgress(
        context,
        l10n.settingsDeleting,
        auth.deleteAccount,
      );
    }
  }
  if (failure == null) {
    // The session's messages are cleared as the sign-in screen comes in.
    showOnSignIn(l10n.settingsDeleted, kind: AppSnackbarKind.success);
  } else {
    AppSnackbar.showError(friendlyMessage(failure), messenger: messenger);
  }
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
    final l10n = context.l10n;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(l10n.settingsReauthTitle),
        content: Text(l10n.settingsReauthProvider(provider)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('reauth-continue'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.settingsReauthContinueWith(provider)),
          ),
        ],
      ),
    );
    if (go != true) return cancelled;
  }
  if (!context.mounted) return cancelled;
  return _withProgress(
    context,
    context.l10n.settingsReauthChecking,
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
        content: Semantics(
          liveRegion: true,
          child: Row(
            children: [
              const SizedBox.square(
                dimension: AppSizes.buttonSpinner,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: Text(label)),
            ],
          ),
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
  bool _missing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _controller.text;
    if (password.isEmpty) {
      setState(() => _missing = true);
      return;
    }
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.settingsReauthTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.settingsReauthPassword),
          const SizedBox(height: AppSpacing.lg),
          AutofillGroup(
            child: AppPasswordField(
              key: const Key('reauth-password'),
              controller: _controller,
              autofocus: true,
              label: l10n.authPasswordLabel,
              textInputAction: TextInputAction.done,
              errorText: _missing ? l10n.settingsReauthPasswordMissing : null,
              onChanged: (_) {
                if (_missing) setState(() => _missing = false);
              },
              onFieldSubmitted: (_) => _submit(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('reauth-continue'),
          onPressed: _submit,
          child: Text(l10n.settingsReauthContinue),
        ),
      ],
    );
  }
}
