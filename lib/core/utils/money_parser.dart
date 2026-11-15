import 'package:intl/intl.dart';

import '../../models/currency_info.dart';
import '../../models/money.dart';
import '../errors/app_failure.dart';
import 'app_locale.dart';

/// Result of [MoneyParser.parse].
sealed class MoneyParseResult {
  const MoneyParseResult();
}

/// The input was a valid positive amount.
final class MoneyParsed extends MoneyParseResult {
  const MoneyParsed(this.value);
  final Money value;
}

/// The input was rejected; [key] is a message key for `friendlyMessage`.
final class MoneyParseError extends MoneyParseResult {
  const MoneyParseError(this.key);

  /// One of `amount_required`, `amount_invalid`, `amount_not_positive`,
  /// `amount_too_many_decimals`, `amount_too_large`.
  final String key;

  /// The same error as a validation failure for the `amount` field.
  AppFailure get failure => AppFailure.validation(field: 'amount', key: key);
}

/// Parses amounts typed by the user into integer minor units.
///
/// * Accepts the locale's grouping and decimal separators, and also `.` or
///   `,` as the decimal mark when that is unambiguous: `12,5` is 12.5 in
///   any locale, while `1,234` in en_US (and `1.234` in de_DE) is a
///   thousands group.
/// * Spaces, no-break spaces and apostrophes are treated as grouping.
/// * A leading currency symbol or code is ignored.
/// * Rejects more fraction digits than the currency has (so `12.5` JPY is
///   rejected), zero, negatives and anything above [Money.maxAmountMinor].
abstract final class MoneyParser {
  static final RegExp _groupingNoise = RegExp(r"[\s  '’_]");
  static final RegExp _allowed = RegExp(r'^[0-9.,]+$');

  static MoneyParseResult parse(
    String input, {
    required String currency,
    String? locale,
  }) {
    final info = CurrencyInfo.of(currency);
    final symbols = NumberFormat.decimalPattern(
      AppLocale.normalize(locale ?? Intl.defaultLocale),
    ).symbols;

    var text = input.trim();
    for (final prefix in {info.symbol, info.code, info.code.toLowerCase()}) {
      text = text.replaceAll(prefix, '');
    }
    text = text.replaceAll(_groupingNoise, '');
    if (text.isEmpty) return const MoneyParseError('amount_required');
    if (text.startsWith('-') || text.startsWith('−')) {
      return const MoneyParseError('amount_not_positive');
    }
    if (text.startsWith('+')) {
      text = text.substring(1);
    }
    if (!_allowed.hasMatch(text)) {
      return const MoneyParseError('amount_invalid');
    }

    final decimalIndex = _decimalMarkIndex(
      text,
      localeDecimal: symbols.DECIMAL_SEP,
      localeGroup: symbols.GROUP_SEP,
    );
    final integerText = decimalIndex == null
        ? text
        : text.substring(0, decimalIndex);
    final fractionText = decimalIndex == null
        ? ''
        : text.substring(decimalIndex + 1);

    // The fraction may not contain separators; the integer part may only
    // use them between digits.
    if (fractionText.contains(RegExp('[.,]'))) {
      return const MoneyParseError('amount_invalid');
    }
    if (integerText.isNotEmpty &&
        (integerText.startsWith(RegExp('[.,]')) ||
            RegExp(r'[.,]$').hasMatch(integerText) ||
            integerText.contains(RegExp('[.,]{2}')))) {
      return const MoneyParseError('amount_invalid');
    }
    if (!_validGrouping(
      integerText,
      decimalIndex == null ? null : text[decimalIndex],
    )) {
      return const MoneyParseError('amount_invalid');
    }
    final integerDigits = integerText.replaceAll(RegExp('[.,]'), '');
    if (integerDigits.isEmpty && fractionText.isEmpty) {
      return const MoneyParseError('amount_invalid');
    }
    if (fractionText.length > info.decimals) {
      return const MoneyParseError('amount_too_many_decimals');
    }
    final significant = integerDigits.replaceFirst(RegExp('^0+'), '');
    if (significant.length > 12) {
      return const MoneyParseError('amount_too_large');
    }

    final major = significant.isEmpty ? 0 : int.parse(significant);
    final minorPart = fractionText.isEmpty
        ? 0
        : int.parse(fractionText.padRight(info.decimals, '0'));
    final amountMinor = major * info.minorPerMajor + minorPart;

    if (amountMinor <= 0) return const MoneyParseError('amount_not_positive');
    if (amountMinor > Money.maxAmountMinor) {
      return const MoneyParseError('amount_too_large');
    }
    return MoneyParsed(Money(amountMinor, currency));
  }

  /// Validator for a form field: null when valid, else friendly copy.
  static String? validate(
    String? input, {
    required String currency,
    String? locale,
    required String Function(AppFailure failure) describe,
  }) {
    final result = parse(input ?? '', currency: currency, locale: locale);
    return switch (result) {
      MoneyParsed() => null,
      MoneyParseError() => describe(result.failure),
    };
  }

  /// Grouping in the integer part uses one separator (not the decimal
  /// mark) and groups of 2 or 3 digits after the first (3 for western,
  /// 2 for Indian lakh grouping).
  static bool _validGrouping(String integerText, String? decimalMark) {
    final separators = integerText.replaceAll(RegExp('[0-9]'), '').split('');
    if (separators.isEmpty) return true;
    final first = separators.first;
    if (separators.any((s) => s != first) || first == decimalMark) {
      return false;
    }
    final groups = integerText.split(first);
    for (var i = 1; i < groups.length; i++) {
      final length = groups[i].length;
      if (length != 2 && length != 3) return false;
    }
    return groups.last.length == 3;
  }

  /// Index of the decimal mark in [text] (digits, `.` and `,` only), or
  /// null when there is none.
  static int? _decimalMarkIndex(
    String text, {
    required String localeDecimal,
    required String localeGroup,
  }) {
    final lastDot = text.lastIndexOf('.');
    final lastComma = text.lastIndexOf(',');
    if (lastDot >= 0 && lastComma >= 0) {
      // Both present: the last one is the decimal mark.
      return lastDot > lastComma ? lastDot : lastComma;
    }
    final index = lastDot >= 0 ? lastDot : lastComma;
    if (index < 0) return null;
    final mark = text[index];
    if (text.indexOf(mark) != index) {
      // The same mark more than once can only be grouping.
      return null;
    }
    if (mark == localeDecimal) return index;
    final digitsAfter = text.length - index - 1;
    if (mark == localeGroup && digitsAfter == 3) return null;
    return index;
  }
}
