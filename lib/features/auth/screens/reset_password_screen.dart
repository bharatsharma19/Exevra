import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/validators.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';

/// Shown while a recovery session is open (from the reset code or the
/// email link). The rest of the app stays closed until a new password is
/// set; cancelling signs out.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  AppFailure? _failure;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _failure = null);
    final failure = await ref
        .read(authControllerProvider.notifier)
        .setNewPassword(_password.text);
    if (!mounted) return;
    if (failure == null) {
      TextInput.finishAutofillContext();
    } else {
      setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final email = auth.user?.email;
    final l10n = context.l10n;

    return PopScope(
      canPop: false,
      child: AuthScaffold(
        title: l10n.authResetTitle,
        subtitle: email == null
            ? l10n.authResetSubtitle
            : l10n.authResetSubtitleFor(email),
        icon: Icons.password_rounded,
        content: [
          if (_failure != null) ...[
            AuthMessage(friendlyMessage(_failure!)),
            const SizedBox(height: AppSpacing.lg),
          ],
          AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PasswordField(
                    controller: _password,
                    label: l10n.authNewPasswordLabel,
                    isNewPassword: true,
                    textInputAction: TextInputAction.next,
                    validator: Validators.validateNewPassword,
                    helperText: l10n.authPasswordRules,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PasswordField(
                    controller: _confirm,
                    label: l10n.authConfirmNewPasswordLabel,
                    isNewPassword: true,
                    validator: Validators.confirmPassword(() => _password.text),
                    onSubmitted: (_) => unawaited(_submit()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AuthPrimaryButton(
            key: const Key('reset-save'),
            label: l10n.authSavePassword,
            busy: auth.isLoading,
            onPressed: () => unawaited(_submit()),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: auth.isLoading
                ? null
                : () => unawaited(
                    ref.read(authControllerProvider.notifier).cancelRecovery(),
                  ),
            child: Text(l10n.authCancelAndSignOut),
          ),
        ],
      ),
    );
  }
}
