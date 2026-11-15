import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/router/navigation.dart';
import '../../../core/utils/validators.dart';
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
  Timer? _ticker;
  AppFailure? _failure;
  String? _notice;

  @override
  void dispose() {
    _ticker?.cancel();
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
        _notice =
            'If an account exists for this address, we emailed it a '
            '6-digit code.';
        _resendAt = DateTime.now().add(_resendCooldown);
        _ticker?.cancel();
        _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) return;
          setState(() {});
          if (DateTime.now().isAfter(_resendAt!)) timer.cancel();
        });
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
    final resendAt = _resendAt;
    final wait = resendAt == null
        ? 0
        : resendAt.difference(DateTime.now()).inSeconds + 1;
    final canResend = !busy && wait <= 0;

    return AuthScaffold(
      title: _codeSent ? 'Enter the code' : 'Reset your password',
      subtitle: _codeSent
          ? 'Enter the 6-digit code we emailed to ${_email.text.trim()} and '
                'choose a new password.'
          : "Enter your account's email address and we'll send you a "
                '6-digit code.',
      icon: Icons.lock_reset_rounded,
      onBack: _back,
      content: [
        if (_failure != null) ...[
          AuthMessage(friendlyMessage(_failure!)),
          const SizedBox(height: 16),
        ] else if (_notice != null) ...[
          AuthMessage(_notice!, isError: false),
          const SizedBox(height: 16),
        ],
        if (!_codeSent) ...[
          AutofillGroup(
            child: Form(
              key: _emailFormKey,
              child: EmailField(
                controller: _email,
                textInputAction: TextInputAction.done,
                validator: Validators.validateEmail,
              ),
            ),
          ),
          const SizedBox(height: 20),
          AuthPrimaryButton(
            label: 'Send code',
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
                  const SizedBox(height: 16),
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
                    onSubmitted: (_) => unawaited(_reset()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          AuthPrimaryButton(
            label: 'Set new password',
            busy: busy,
            onPressed: () => unawaited(_reset()),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: canResend ? () => unawaited(_sendCode()) : null,
            child: Text(canResend ? 'Resend code' : 'Resend code in ${wait}s'),
          ),
        ],
      ],
    );
  }
}
