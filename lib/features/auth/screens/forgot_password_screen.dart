import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/router/navigation.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/validators.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';

/// Password reset with a 6-digit code from the email, so it works even
/// when the email is opened on another device.
///
/// Step 1 asks for the address; step 2 takes the code and the new
/// password. Verifying the code starts a recovery session and the new
/// password is set right away; the user ends up signed in.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  static const Duration _resendCooldown = Duration(seconds: 60);

  final _emailFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail ?? '',
  );
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _codeSent = false;
  DateTime? _resendAt;
  AppFailure? _failure;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  AuthController get _controller => ref.read(authControllerProvider.notifier);

  Future<void> _sendCode() async {
    if (!_codeSent && !(_emailFormKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _failure = null;
      _notice = null;
    });
    final failure = await _controller.sendPasswordResetCode(_email.text);
    if (!mounted) return;
    setState(() {
      _failure = failure;
      if (failure == null) {
        _codeSent = true;
        _notice = context.l10n.authCodeSent;
        _resendAt = DateTime.now().add(_resendCooldown);
      }
    });
  }

  Future<void> _reset() async {
    if (!(_resetFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _failure = null;
      _notice = null;
    });
    final failure = await _controller.resetPasswordWithCode(
      email: _email.text,
      code: _code.text,
      newPassword: _password.text,
    );
    if (!mounted) return;
    if (failure == null) {
      TextInput.finishAutofillContext();
    } else {
      setState(() => _failure = failure);
    }
  }

  void _back() {
    if (_codeSent) {
      setState(() {
        _codeSent = false;
        _failure = null;
        _notice = null;
        _code.clear();
      });
    } else {
      popOrGo(context, AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(authControllerProvider.select((s) => s.isLoading));
    final l10n = context.l10n;

    return AuthScaffold(
      title: _codeSent ? l10n.authCodeTitle : l10n.authForgotTitle,
      subtitle: _codeSent
          ? l10n.authCodeSubtitle(_email.text.trim())
          : l10n.authForgotSubtitle,
      icon: Icons.lock_reset_rounded,
      onBack: _back,
      content: [
        if (_failure != null) ...[
          AuthMessage(friendlyMessage(_failure!)),
          const SizedBox(height: AppSpacing.lg),
        ] else if (_notice != null) ...[
          AuthMessage(_notice!, isError: false),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (!_codeSent) ...[
          AutofillGroup(
            child: Form(
              key: _emailFormKey,
              child: EmailField(
                controller: _email,
                textInputAction: TextInputAction.done,
                validator: Validators.validateEmail,
                onSubmitted: (_) => unawaited(_sendCode()),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AuthPrimaryButton(
            key: const Key('forgot-send'),
            label: l10n.authSendCode,
            busy: busy,
            onPressed: () => unawaited(_sendCode()),
          ),
        ] else ...[
          AutofillGroup(
            child: Form(
              key: _resetFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OtpField(
                    controller: _code,
                    textInputAction: TextInputAction.next,
                    validator: Validators.validateOtp,
                  ),
                  const SizedBox(height: AppSpacing.lg),
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
                    onSubmitted: (_) => unawaited(_reset()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AuthPrimaryButton(
            key: const Key('forgot-reset'),
            label: l10n.authSetNewPassword,
            busy: busy,
            onPressed: () => unawaited(_reset()),
          ),
          const SizedBox(height: AppSpacing.sm),
          ResendCooldownButton(
            key: const Key('forgot-resend'),
            label: l10n.authResendCode,
            availableAt: _resendAt,
            busy: busy,
            onResend: () => unawaited(_sendCode()),
          ),
        ],
      ],
    );
  }
}
