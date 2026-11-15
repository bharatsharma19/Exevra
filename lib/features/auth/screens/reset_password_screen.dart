import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/utils/validators.dart';
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

    return PopScope(
      canPop: false,
      child: AuthScaffold(
        title: 'Choose a new password',
        subtitle: email == null
            ? 'Set a new password to finish resetting it.'
            : 'Set a new password for $email to finish resetting it.',
        icon: Icons.password_rounded,
        content: [
          if (_failure != null) ...[
            AuthMessage(friendlyMessage(_failure!)),
            const SizedBox(height: 16),
          ],
          AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PasswordField(
                    controller: _password,
                    label: 'New password',
                    isNewPassword: true,
                    textInputAction: TextInputAction.next,
                    validator: Validators.validateNewPassword,
                    helperText:
                        'At least 8 characters with upper and lower case '
                        'letters and a number.',
                  ),
                  const SizedBox(height: 16),
                  PasswordField(
                    controller: _confirm,
                    label: 'Confirm new password',
                    isNewPassword: true,
                    validator: Validators.confirmPassword(() => _password.text),
                    onSubmitted: (_) => unawaited(_submit()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          AuthPrimaryButton(
            label: 'Save password',
            busy: auth.isLoading,
            onPressed: () => unawaited(_submit()),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: auth.isLoading
                ? null
                : () => unawaited(
                    ref.read(authControllerProvider.notifier).cancelRecovery(),
                  ),
            child: const Text('Cancel and sign out'),
          ),
        ],
      ),
    );
  }
}
