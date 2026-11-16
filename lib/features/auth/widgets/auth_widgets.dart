import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';

export 'resend_cooldown.dart';

/// Shared frame of the auth screens: a round icon (or the brand mark), the
/// title, a subtitle and a card with the form.
///
/// The page scrolls, so the form stays reachable with the keyboard open,
/// on a 320 dp screen and with 200% text. The keyboard closes when the
/// page is dragged.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.content,
    this.footer = const [],
    this.onBack,
    this.icon = Icons.auto_graph_rounded,
    this.showBrand = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> content;
  final List<Widget> footer;

  /// Shows a back button when set.
  final VoidCallback? onBack;

  /// Round icon above the title (unless [showBrand]).
  final IconData icon;

  /// Shows the Exevra logo instead of [icon].
  final bool showBrand;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: onBack == null
          ? null
          : AppBar(
              leading: BackButton(onPressed: onBack),
              automaticallyImplyLeading: false,
            ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: showBrand
                        ? const BrandMark(size: 30)
                        : StateIcon(
                            icon: icon,
                            background: palette.accentContainer,
                            foreground: palette.onAccentContainer,
                          ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: content,
                    ),
                  ),
                  ...footer,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One inline message above the form (an error, or a notice such as "We
/// sent a new email"). It is a live region, so screen readers read it when
/// it appears; the icon and the text carry the meaning, not only the
/// colour.
class AuthMessage extends StatelessWidget {
  const AuthMessage(this.message, {super.key, this.isError = true});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final background = isError
        ? palette.dangerContainer
        : palette.infoContainer;
    final foreground = isError
        ? palette.onDangerContainer
        : palette.onInfoContainer;
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadius.mdAll,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isError ? Icons.error_outline_rounded : Icons.info_outline,
                color: foreground,
                size: AppSizes.iconSm + 2,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Email field with autofill.
class EmailField extends StatelessWidget {
  const EmailField({
    super.key,
    required this.controller,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction = TextInputAction.next,
    this.enabled = true,
  });

  final TextEditingController controller;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: textInputAction,
      autofillHints: const [AutofillHints.email],
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: l10n.authEmailLabel,
        hintText: l10n.authEmailHint,
        prefixIcon: const Icon(Icons.alternate_email_rounded),
      ),
    );
  }
}

/// Password field with a show/hide toggle (with a tooltip) and autofill:
/// the kit's [AppPasswordField] with the auth screens' defaults.
class PasswordField extends StatelessWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label,
    this.isNewPassword = false,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction = TextInputAction.done,
    this.helperText,
    this.autofocus = false,
  });

  final TextEditingController controller;

  /// Defaults to "Password".
  final String? label;

  /// Uses the `newPassword` autofill hint (password managers offer to
  /// generate and save one).
  final bool isNewPassword;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;
  final String? helperText;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => AppPasswordField(
    controller: controller,
    label: label ?? context.l10n.authPasswordLabel,
    isNewPassword: isNewPassword,
    validator: validator,
    onChanged: onChanged,
    onFieldSubmitted: onSubmitted,
    textInputAction: textInputAction,
    helperText: helperText,
    autofocus: autofocus,
  );
}

/// 6-digit code field (one-time-code autofill).
class OtpField extends StatelessWidget {
  const OtpField({
    super.key,
    required this.controller,
    this.validator,
    this.onSubmitted,
    this.textInputAction = TextInputAction.done,
  });

  final TextEditingController controller;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      textInputAction: textInputAction,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      validator: validator,
      onFieldSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: context.l10n.authCodeLabel,
        prefixIcon: const Icon(Icons.pin_outlined),
      ),
    );
  }
}

/// Full-width primary button with a busy state (the kit's
/// [LoadingButton]).
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) =>
      LoadingButton(label: label, onPressed: onPressed, isLoading: busy);
}

/// "or" between the email form and the Google / Apple buttons.
class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(
              context.l10n.authOr,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

/// "Don't have an account? Sign up": a prompt and a text button that wrap
/// onto two lines when they do not fit.
class AuthSwitchPrompt extends StatelessWidget {
  const AuthSwitchPrompt({
    super.key,
    required this.prompt,
    required this.action,
    required this.onPressed,
  });

  final String prompt;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            prompt,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
          ),
          TextButton(onPressed: onPressed, child: Text(action)),
        ],
      ),
    );
  }
}
