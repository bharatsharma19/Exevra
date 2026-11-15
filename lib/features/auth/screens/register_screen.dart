import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/router/navigation.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/validators.dart';
import '../../../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';

/// Opens a legal page in the browser.
Future<void> openLegalPage(Uri url) async {
  try {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      AppLogger.warn('Could not open a legal page');
    }
  } on Object catch (e) {
    AppLogger.warn('Could not open a legal page', e.runtimeType);
  }
}

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late final TapGestureRecognizer _termsTap = TapGestureRecognizer()
    ..onTap = () => unawaited(openLegalPage(AppConfig.environment.termsUrl));
  late final TapGestureRecognizer _privacyTap = TapGestureRecognizer()
    ..onTap = () => unawaited(openLegalPage(AppConfig.environment.privacyUrl));
  bool _acceptedTerms = false;
  AppFailure? _failure;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  void _clearFailure() {
    if (_failure != null) setState(() => _failure = null);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    AppHaptics.light();
    setState(() => _failure = null);
    final failure = await ref
        .read(authControllerProvider.notifier)
        .signUp(
          email: _email.text,
          password: _password.text,
          displayName: _name.text.trim(),
        );
    if (!mounted) return;
    if (failure == null) {
      TextInput.finishAutofillContext();
    } else {
      setState(() => _failure = failure);
    }
  }

  String _emailQuery() {
    final email = _email.text.trim();
    return email.isEmpty ? '' : '?email=${Uri.encodeComponent(email)}';
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(authControllerProvider.select((s) => s.isLoading));
    final scheme = Theme.of(context).colorScheme;
    final failure = _failure;

    return AuthScaffold(
      title: 'Create your account',
      subtitle: 'Track personal spending and split costs with others',
      onBack: () => popOrGo(context, AppRoutes.login),
      content: [
        if (failure != null) ...[
          AuthMessage(friendlyMessage(failure)),
          if (failure is AccountExistsFailure)
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: () =>
                      context.go('${AppRoutes.login}${_emailQuery()}'),
                  child: const Text('Sign in'),
                ),
                TextButton(
                  onPressed: () =>
                      context.go('${AppRoutes.forgotPassword}${_emailQuery()}'),
                  child: const Text('Reset password'),
                ),
              ],
            ),
          const SizedBox(height: 16),
        ],
        AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  validator: Validators.validateDisplayName,
                  onChanged: (_) => _clearFailure(),
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                EmailField(
                  controller: _email,
                  validator: Validators.validateEmail,
                  onChanged: (_) => _clearFailure(),
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: _password,
                  isNewPassword: true,
                  textInputAction: TextInputAction.next,
                  validator: Validators.validateNewPassword,
                  helperText:
                      'At least 8 characters with upper and lower case '
                      'letters and a number.',
                  onChanged: (_) => _clearFailure(),
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: _confirm,
                  label: 'Confirm password',
                  isNewPassword: true,
                  validator: Validators.confirmPassword(() => _password.text),
                  onSubmitted: (_) => unawaited(_submit()),
                ),
                const SizedBox(height: 12),
                FormField<bool>(
                  initialValue: _acceptedTerms,
                  validator: (_) => _acceptedTerms
                      ? null
                      : friendlyMessageForKey('terms_required'),
                  builder: (field) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _acceptedTerms,
                            onChanged: (value) {
                              setState(() => _acceptedTerms = value ?? false);
                              field.didChange(_acceptedTerms);
                            },
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text.rich(
                                TextSpan(
                                  text: 'I agree to the ',
                                  children: [
                                    TextSpan(
                                      text: 'Terms of Service',
                                      style: TextStyle(
                                        color: scheme.primary,
                                        decoration: TextDecoration.underline,
                                      ),
                                      recognizer: _termsTap,
                                    ),
                                    const TextSpan(text: ' and '),
                                    TextSpan(
                                      text: 'Privacy Policy',
                                      style: TextStyle(
                                        color: scheme.primary,
                                        decoration: TextDecoration.underline,
                                      ),
                                      recognizer: _privacyTap,
                                    ),
                                    const TextSpan(text: '.'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (field.hasError)
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Text(
                            field.errorText!,
                            style: TextStyle(color: scheme.error, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        AuthPrimaryButton(
          label: 'Create account',
          busy: busy,
          onPressed: () => unawaited(_submit()),
        ),
      ],
      footer: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Already have an account?',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            TextButton(
              onPressed: () => popOrGo(context, AppRoutes.login),
              child: const Text('Sign in'),
            ),
          ],
        ),
      ],
    );
  }
}
