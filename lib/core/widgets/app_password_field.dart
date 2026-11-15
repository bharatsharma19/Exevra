import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// A password input with a labelled show/hide toggle (48 dp target, tooltip
/// "Show password" / "Hide password") and password autofill hints.
class AppPasswordField extends StatefulWidget {
  /// Creates a password field.
  const AppPasswordField({
    required this.label,
    this.controller,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.focusNode,
    this.textInputAction,
    this.helperText,
    this.errorText,
    this.autofocus = false,
    this.enabled = true,
    this.isNewPassword = false,
    super.key,
  });

  /// Field label, also its screen reader name.
  final String label;

  /// Text controller.
  final TextEditingController? controller;

  /// Form validator.
  final FormFieldValidator<String>? validator;

  /// Called on every edit.
  final ValueChanged<String>? onChanged;

  /// Called when the user submits from the keyboard.
  final ValueChanged<String>? onFieldSubmitted;

  /// Focus node.
  final FocusNode? focusNode;

  /// Keyboard action button.
  final TextInputAction? textInputAction;

  /// Supporting text under the field (password rules).
  final String? helperText;

  /// Error text under the field.
  final String? errorText;

  /// Whether to focus the field on build.
  final bool autofocus;

  /// Whether the field accepts input.
  final bool enabled;

  /// Hints a new password (sign-up, reset) instead of the saved one.
  final bool isNewPassword;

  @override
  State<AppPasswordField> createState() => _AppPasswordFieldState();
}

class _AppPasswordFieldState extends State<AppPasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      obscureText: _obscured,
      enableSuggestions: false,
      autocorrect: false,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: widget.textInputAction,
      autofillHints: [
        if (widget.isNewPassword)
          AutofillHints.newPassword
        else
          AutofillHints.password,
      ],
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onFieldSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helperText,
        errorText: widget.errorText,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: _obscured ? l10n.showPassword : l10n.hidePassword,
          icon: Icon(
            _obscured
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          onPressed: widget.enabled
              ? () => setState(() => _obscured = !_obscured)
              : null,
        ),
      ),
    );
  }
}
