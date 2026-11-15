import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/validators.dart';
import '../../../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';

/// Sign in with Apple is offered on iOS only (App Store guideline 4.8 and
/// the native flow); Android users have Google and email.
bool get showAppleSignIn =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail ?? '',
  );
  final _password = TextEditingController();
  AppFailure? _failure;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _clearFailure() {
    if (_failure != null) setState(() => _failure = null);
  }

  Future<void> _act(Future<AppFailure?> Function() action) async {
    setState(() => _failure = null);
    final failure = await action();
    if (!mounted) return;
    if (failure == null) {
      TextInput.finishAutofillContext();
    } else {
      setState(() => _failure = failure);
    }
  }

  Future<void> _signIn() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    AppHaptics.light();
    await _act(
      () => ref
          .read(authControllerProvider.notifier)
          .signIn(_email.text, _password.text),
    );
  }

  String _withReturnTo(String path) {
    final returnTo = safeReturnTo(
      GoRouterState.of(context).uri.queryParameters['returnTo'],
    );
    return returnTo == null
        ? path
        : '$path?returnTo=${Uri.encodeComponent(returnTo)}';
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(authControllerProvider.select((s) => s.isLoading));
    final scheme = Theme.of(context).colorScheme;
    final controller = ref.read(authControllerProvider.notifier);
    final googleConfigured = AppConfig.environment.isGoogleSignInConfigured;

    return AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to manage personal and shared expenses',
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
                EmailField(
                  controller: _email,
                  validator: Validators.validateEmail,
                  onChanged: (_) => _clearFailure(),
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: _password,
                  validator: Validators.validateLoginPassword,
                  onChanged: (_) => _clearFailure(),
                  onSubmitted: (_) => unawaited(_signIn()),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              final email = _email.text.trim();
              unawaited(
                context.push(
                  email.isEmpty
                      ? AppRoutes.forgotPassword
                      : '${AppRoutes.forgotPassword}?email=${Uri.encodeComponent(email)}',
                ),
              );
            },
            child: const Text('Forgot password?'),
          ),
        ),
        const SizedBox(height: 8),
        AuthPrimaryButton(
          label: 'Sign in',
          busy: busy,
          onPressed: () => unawaited(_signIn()),
        ),
        if (googleConfigured || showAppleSignIn) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (googleConfigured)
          OutlinedButton(
            onPressed: busy
                ? null
                : () => unawaited(_act(controller.signInWithGoogle)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Continue with Google'),
          ),
        if (showAppleSignIn) ...[
          const SizedBox(height: 12),
          SignInWithAppleButton(
            onPressed: () {
              if (!busy) unawaited(_act(controller.signInWithApple));
            },
            style: Theme.of(context).brightness == Brightness.dark
                ? SignInWithAppleButtonStyle.white
                : SignInWithAppleButtonStyle.black,
          ),
        ],
      ],
      footer: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Don't have an account?",
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            TextButton(
              onPressed: () =>
                  unawaited(context.push(_withReturnTo(AppRoutes.register))),
              child: const Text('Sign up'),
            ),
          ],
        ),
      ],
    );
  }
}
