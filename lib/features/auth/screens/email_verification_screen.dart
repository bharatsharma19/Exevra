import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/utils/validators.dart';
import '../../../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';

/// Waits for the email address to be confirmed. The user can follow the
/// link in the email, type the 6-digit code from it (works on any
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
  Timer? _ticker;
  AppFailure? _failure;
  String? _notice;
  bool _needsPassword = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Redraws the resend countdown.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final at = ref.read(authControllerProvider).resendAvailableAt;
      if (mounted && at != null && !DateTime.now().isAfter(at)) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
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
    _show(
      failure: failure,
      notice: failure == null ? 'We sent a new email. Check your inbox.' : null,
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
        _show(notice: 'Enter your password to continue.');
      case VerificationCheck.notYet:
        _show(
          failure: failure,
          notice: failure == null
              ? "Your email isn't confirmed yet. Open the link or enter the "
                    'code from the email.'
              : null,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final email = auth.verificationEmail ?? '';
    final scheme = Theme.of(context).colorScheme;
    final at = auth.resendAvailableAt;
    final wait = at == null ? 0 : at.difference(DateTime.now()).inSeconds + 1;
    final canResend = !auth.isLoading && (at == null || wait <= 0);

    return AuthScaffold(
      title: 'Verify your email',
      subtitle: 'We sent a confirmation link and a 6-digit code to',
      icon: Icons.mark_email_unread_outlined,
      content: [
        Text(
          email,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        if (_failure != null) ...[
          AuthMessage(friendlyMessage(_failure!)),
          const SizedBox(height: 16),
        ] else if (_notice != null) ...[
          AuthMessage(_notice!, isError: false),
          const SizedBox(height: 16),
        ],
        Form(
          key: _codeFormKey,
          child: OtpField(
            controller: _code,
            validator: Validators.validateOtp,
            onSubmitted: (_) => unawaited(_verifyCode()),
          ),
        ),
        const SizedBox(height: 12),
        AuthPrimaryButton(
          label: 'Verify code',
          busy: auth.isLoading,
          onPressed: () => unawaited(_verifyCode()),
        ),
        const SizedBox(height: 20),
        if (_needsPassword) ...[
          AutofillGroup(
            child: PasswordField(
              controller: _password,
              onSubmitted: (_) => unawaited(_check()),
            ),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton(
          onPressed: auth.isLoading ? null : () => unawaited(_check()),
          child: const Text("I've confirmed my email"),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: canResend ? () => unawaited(_resend()) : null,
          child: Text(canResend ? 'Resend email' : 'Resend email in ${wait}s'),
        ),
      ],
      footer: [
        const SizedBox(height: 16),
        Text(
          "Can't find it? Check your spam folder.",
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        TextButton(
          onPressed: auth.isLoading
              ? null
              : () => unawaited(_controller.cancelVerification()),
          child: const Text('Use a different email'),
        ),
      ],
    );
  }
}
