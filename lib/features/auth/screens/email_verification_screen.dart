import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/validators.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';

/// Waits for the email address to be confirmed. The user can follow the
/// link in the email, type the 8-digit code from it (works on any
/// device), resend it, or start over with another address.
class EmailVerificationScreen extends ConsumerStatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  ConsumerState<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState
    extends ConsumerState<EmailVerificationScreen>
    with WidgetsBindingObserver {
  final _codeFormKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _password = TextEditingController();
  AppFailure? _failure;
  String? _notice;
  bool _needsPassword = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the mail app: check quietly whether the link was used.
    if (state == AppLifecycleState.resumed) unawaited(_check(quiet: true));
  }

  AuthController get _controller => ref.read(authControllerProvider.notifier);

  void _show({AppFailure? failure, String? notice}) {
    if (!mounted) return;
    setState(() {
      _failure = failure;
      _notice = notice;
    });
  }

  Future<void> _resend() async {
    _show();
    final failure = await _controller.resendVerification();
    if (!mounted) return;
    _show(
      failure: failure,
      notice: failure == null ? context.l10n.authEmailResent : null,
    );
  }

  Future<void> _verifyCode() async {
    if (!(_codeFormKey.currentState?.validate() ?? false)) return;
    _show();
    final failure = await _controller.verifySignupCode(_code.text);
    _show(failure: failure);
  }

  Future<void> _check({bool quiet = false}) async {
    if (ref.read(authControllerProvider).isLoading) return;
    if (quiet && _needsPassword) return;
    if (!quiet) _show();
    final (result, failure) = await _controller.checkVerified(
      password: _password.text.isEmpty ? null : _password.text,
    );
    if (!mounted || quiet) return;
    switch (result) {
      case VerificationCheck.verified:
        _show(); // The router moves on.
      case VerificationCheck.needsPassword:
        setState(() => _needsPassword = true);
        _show(notice: context.l10n.authEnterPasswordToContinue);
      case VerificationCheck.notYet:
        _show(
          failure: failure,
          notice: failure == null ? context.l10n.authNotConfirmedYet : null,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final email = auth.verificationEmail ?? '';
    final l10n = context.l10n;
    final palette = context.palette;

    return AuthScaffold(
      title: l10n.authVerifyTitle,
      subtitle: l10n.authVerifySubtitle,
      icon: Icons.mark_email_unread_outlined,
      content: [
        Text(
          email,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_failure != null) ...[
          AuthMessage(friendlyMessage(_failure!)),
          const SizedBox(height: AppSpacing.lg),
        ] else if (_notice != null) ...[
          AuthMessage(_notice!, isError: false),
          const SizedBox(height: AppSpacing.lg),
        ],
        Form(
          key: _codeFormKey,
          child: OtpField(
            controller: _code,
            validator: Validators.validateOtp,
            onSubmitted: (_) => unawaited(_verifyCode()),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AuthPrimaryButton(
          key: const Key('verify-code'),
          label: l10n.authVerifyCode,
          busy: auth.isLoading,
          onPressed: () => unawaited(_verifyCode()),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (_needsPassword) ...[
          AutofillGroup(
            child: PasswordField(
              controller: _password,
              autofocus: true,
              onSubmitted: (_) => unawaited(_check()),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        OutlinedButton(
          key: const Key('verify-confirmed'),
          onPressed: auth.isLoading ? null : () => unawaited(_check()),
          child: Text(l10n.authVerifyConfirmed),
        ),
        const SizedBox(height: AppSpacing.sm),
        ResendCooldownButton(
          key: const Key('verify-resend'),
          label: l10n.authResendEmail,
          availableAt: auth.resendAvailableAt,
          busy: auth.isLoading,
          onResend: () => unawaited(_resend()),
        ),
      ],
      footer: [
        const SizedBox(height: AppSpacing.lg),
        Text(
          l10n.authCheckSpam,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
        ),
        TextButton(
          onPressed: auth.isLoading
              ? null
              : () => unawaited(_controller.cancelVerification()),
          child: Text(l10n.authUseDifferentEmail),
        ),
      ],
    );
  }
}
