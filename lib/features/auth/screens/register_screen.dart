import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/legal_links.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/router/navigation.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/validators.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.links});

  /// Terms and privacy pages; defaults to this build's.
  final LegalLinks? links;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _acceptedTerms = false;
  AppFailure? _failure;

  LegalLinks get _links => widget.links ?? LegalLinks.current;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
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
    final l10n = context.l10n;
    final failure = _failure;

    return AuthScaffold(
      title: l10n.authRegisterTitle,
      subtitle: l10n.authRegisterSubtitle,
      icon: Icons.person_add_alt_1_rounded,
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
                  child: Text(l10n.authSignIn),
                ),
                TextButton(
                  onPressed: () =>
                      context.go('${AppRoutes.forgotPassword}${_emailQuery()}'),
                  child: Text(l10n.authResetPasswordAction),
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.lg),
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
                  decoration: InputDecoration(
                    labelText: l10n.authNameLabel,
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                EmailField(
                  controller: _email,
                  validator: Validators.validateEmail,
                  onChanged: (_) => _clearFailure(),
                ),
                const SizedBox(height: AppSpacing.lg),
                PasswordField(
                  controller: _password,
                  isNewPassword: true,
                  textInputAction: TextInputAction.next,
                  validator: Validators.validateNewPassword,
                  helperText: l10n.authPasswordRules,
                  onChanged: (_) => _clearFailure(),
                ),
                const SizedBox(height: AppSpacing.lg),
                PasswordField(
                  controller: _confirm,
                  label: l10n.authConfirmPasswordLabel,
                  isNewPassword: true,
                  validator: Validators.confirmPassword(() => _password.text),
                  onSubmitted: (_) => unawaited(_submit()),
                ),
                const SizedBox(height: AppSpacing.md),
                _TermsField(
                  accepted: _acceptedTerms,
                  onChanged: (value) => setState(() => _acceptedTerms = value),
                  onOpenTerms: () =>
                      unawaited(openExternal(context, _links.terms)),
                  onOpenPrivacy: () =>
                      unawaited(openExternal(context, _links.privacyPolicy)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AuthPrimaryButton(
          key: const Key('register-submit'),
          label: l10n.authCreateAccount,
          busy: busy,
          onPressed: () => unawaited(_submit()),
        ),
      ],
      footer: [
        AuthSwitchPrompt(
          prompt: l10n.authHaveAccount,
          action: l10n.authSignIn,
          onPressed: () => popOrGo(context, AppRoutes.login),
        ),
      ],
    );
  }
}

/// The required "I agree" checkbox (the whole row toggles it) with the
/// Terms and Privacy links as their own buttons under it, so each is a
/// 48 dp target that screen readers can reach.
class _TermsField extends StatelessWidget {
  const _TermsField({
    required this.accepted,
    required this.onChanged,
    required this.onOpenTerms,
    required this.onOpenPrivacy,
  });

  final bool accepted;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenPrivacy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    return FormField<bool>(
      initialValue: accepted,
      validator: (_) =>
          accepted ? null : friendlyMessageForKey('terms_required'),
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: InkWell(
              key: const Key('register-terms'),
              borderRadius: AppRadius.mdAll,
              onTap: () {
                onChanged(!accepted);
                field.didChange(!accepted);
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: accepted,
                    onChanged: (value) {
                      onChanged(value ?? false);
                      field.didChange(value ?? false);
                    },
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      child: Text(
                        l10n.authAgreeTerms,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              TextButton.icon(
                onPressed: onOpenTerms,
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(l10n.authTermsLink),
              ),
              TextButton.icon(
                onPressed: onOpenPrivacy,
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(l10n.authPrivacyLink),
              ),
            ],
          ),
          if (field.hasError)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: AppSpacing.md),
                child: Text(
                  field.errorText!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.danger),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
