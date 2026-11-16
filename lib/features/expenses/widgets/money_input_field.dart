import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/errors/failure_messages.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/utils/money_parser.dart';

/// A money input that reads amounts the way [MoneyParser] does.
///
/// The kit's `AmountField` turns every comma into a decimal point and
/// rejects grouping, while [MoneyParser] understands the device locale
/// (`1,250.50` in en_IN, `1.250,50` in de_DE, `12,5` anywhere) and the
/// currency's own number of decimals (none for JPY). This field keeps the
/// text as typed (digits, separators and spaces only) and validates and
/// parses it with [MoneyParser], so what the user sees is what is saved.
///
/// The [label] is also the screen reader name, and errors show under the
/// field so they stay visible while the keyboard is open.
class MoneyInputField extends StatelessWidget {
  /// Creates a money field.
  const MoneyInputField({
    required this.controller,
    required this.currency,
    required this.label,
    this.locale,
    this.enabled = true,
    this.helperText,
    this.errorText,
    this.validator,
    this.onChanged,
    this.textInputAction,
    this.large = false,
    super.key,
  });

  /// Text controller. Prefill it with [MoneyFormat.forInput].
  final TextEditingController controller;

  /// ISO code the amount is in; decides the allowed decimals.
  final String currency;

  /// Field label and screen reader name.
  final String label;

  /// Locale for separators; the device locale when null.
  final String? locale;

  /// Whether the field accepts input. A disabled field is read only.
  final bool enabled;

  /// Supporting text under the field.
  final String? helperText;

  /// Error text that overrides the validator's.
  final String? errorText;

  /// Extra validation after the amount parsed (for example a limit).
  final String? Function(MoneyParsed parsed)? validator;

  /// Called on every edit.
  final ValueChanged<String>? onChanged;

  /// Keyboard action.
  final TextInputAction? textInputAction;

  /// Uses the large headline style (the expense sheet's main amount).
  final bool large;

  /// Parses [text] in [currency] with the device locale (or [locale]).
  static MoneyParseResult parse(
    String text, {
    required String currency,
    String? locale,
  }) => MoneyParser.parse(text, currency: currency, locale: locale);

  /// Friendly validation copy for [text], or null when it is a valid
  /// amount.
  static String? validate(
    String? text, {
    required String currency,
    String? locale,
  }) => MoneyParser.validate(
    text,
    currency: currency,
    locale: locale,
    describe: friendlyMessage,
  );

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final base = large ? textTheme.headlineSmall : textTheme.bodyLarge;
    return TextFormField(
      controller: controller,
      enabled: enabled,
      readOnly: !enabled,
      style: base?.copyWith(
        color: enabled ? context.palette.textPrimary : null,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: textInputAction,
      inputFormatters: [MoneyInputFormatter()],
      validator: (value) {
        final invalid = validate(value, currency: currency, locale: locale);
        if (invalid != null) return invalid;
        final parsed = parse(value ?? '', currency: currency, locale: locale);
        if (parsed is MoneyParsed) return validator?.call(parsed);
        return null;
      },
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: '0',
        helperText: helperText,
        helperMaxLines: 3,
        errorText: errorText,
        errorMaxLines: 3,
        prefixText: '${MoneyFormat.symbolOf(currency)} ',
      ),
    );
  }
}

/// Keeps only what an amount can contain: digits, `.` and `,`, and the
/// spaces or apostrophes some locales group with, up to [maxLength]
/// characters. Anything else (letters, a minus sign) is dropped as it is
/// typed; [MoneyParser] decides whether the rest is a valid amount.
class MoneyInputFormatter extends TextInputFormatter {
  static final RegExp _disallowed = RegExp(r"[^0-9.,\s'’]");

  /// Longest text kept.
  static const int maxLength = 24;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned = newValue.text.replaceAll(_disallowed, '');
    if (cleaned.length > maxLength) return oldValue;
    if (cleaned == newValue.text) return newValue;
    final removed = newValue.text.length - cleaned.length;
    final offset = (newValue.selection.baseOffset - removed).clamp(
      0,
      cleaned.length,
    );
    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
