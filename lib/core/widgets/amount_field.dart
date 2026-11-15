import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A money input: decimal keyboard, at most [AmountField.maxDecimals]
/// decimals, a currency prefix and inline helper or error text.
///
/// The field's label is its screen reader name, so always pass a [label]
/// that says what the amount is ("Amount", "Your share"). Validation errors
/// show under the field (from [validator] or [errorText]) instead of in a
/// snackbar, so they stay visible while the keyboard is open.
///
/// ```dart
/// AmountField(
///   controller: _amount,
///   label: 'Amount',
///   currencySymbol: '₹',
///   validator: (v) => (AmountField.parse(v) ?? 0) > 0 ? null : 'Enter an amount',
/// )
/// ```
class AmountField extends StatelessWidget {
  /// Creates an amount field.
  const AmountField({
    required this.label,
    this.controller,
    this.initialValue,
    this.currencySymbol,
    this.hintText,
    this.helperText,
    this.errorText,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.focusNode,
    this.textInputAction,
    this.autofocus = false,
    this.enabled = true,
    this.maxDecimals = 2,
    this.maxWholeDigits = 9,
    super.key,
  }) : assert(
         controller == null || initialValue == null,
         'Pass either controller or initialValue',
       );

  /// Field label, also its screen reader name.
  final String label;

  /// Text controller.
  final TextEditingController? controller;

  /// Initial text when no [controller] is given.
  final String? initialValue;

  /// Currency symbol shown before the amount ("₹").
  final String? currencySymbol;

  /// Placeholder ("0.00").
  final String? hintText;

  /// Supporting text under the field.
  final String? helperText;

  /// Error text under the field; overrides [validator] output.
  final String? errorText;

  /// Form validator.
  final FormFieldValidator<String>? validator;

  /// Called on every accepted edit.
  final ValueChanged<String>? onChanged;

  /// Called when the user submits from the keyboard.
  final ValueChanged<String>? onFieldSubmitted;

  /// Focus node.
  final FocusNode? focusNode;

  /// Keyboard action button.
  final TextInputAction? textInputAction;

  /// Whether to focus the field on build.
  final bool autofocus;

  /// Whether the field accepts input.
  final bool enabled;

  /// Maximum digits after the decimal point.
  final int maxDecimals;

  /// Maximum digits before the decimal point.
  final int maxWholeDigits;

  /// Parses field text ("1250.5", "1,250.50") to a number, or null when it is
  /// empty or not a number.
  static double? parse(String? text) {
    final cleaned = (text ?? '').replaceAll(',', '').trim();
    if (cleaned.isEmpty || cleaned == '.') return null;
    return double.tryParse(cleaned);
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return TextFormField(
      controller: controller,
      initialValue: initialValue,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      style: style,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: textInputAction,
      inputFormatters: [
        AmountInputFormatter(
          maxDecimals: maxDecimals,
          maxWholeDigits: maxWholeDigits,
        ),
      ],
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        helperText: helperText,
        errorText: errorText,
        prefixText: currencySymbol == null ? null : '$currencySymbol ',
      ),
    );
  }
}

/// Accepts only digits and a single decimal point, with at most
/// [maxWholeDigits] digits before it and [maxDecimals] after it. A comma
/// typed as the decimal separator becomes a point. Any other edit is
/// rejected and the previous text is kept.
class AmountInputFormatter extends TextInputFormatter {
  /// Creates the formatter.
  AmountInputFormatter({this.maxDecimals = 2, this.maxWholeDigits = 9})
    : _pattern = RegExp(
        maxDecimals > 0
            ? '^\\d{0,$maxWholeDigits}(\\.\\d{0,$maxDecimals})?\$'
            : '^\\d{0,$maxWholeDigits}\$',
      );

  /// Maximum digits after the decimal point.
  final int maxDecimals;

  /// Maximum digits before the decimal point.
  final int maxWholeDigits;

  final RegExp _pattern;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(',', '.');
    if (!_pattern.hasMatch(text)) return oldValue;
    return newValue.copyWith(text: text);
  }
}
