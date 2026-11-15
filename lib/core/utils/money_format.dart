import 'package:intl/intl.dart';

import '../../models/currency_info.dart';
import '../../models/money.dart';
import 'app_locale.dart';

/// Locale-aware display of [Money] with the currency's own decimals.
abstract final class MoneyFormat {
  /// Full amount, for example `₹1,23,456.78` (en_IN), `1.234,56 €`
  /// (de_DE) or `¥1,200` (JPY has no decimals).
  static String format(Money money, {String? locale}) {
    final info = money.info;
    final formatter = NumberFormat.currency(
      locale: AppLocale.normalize(locale ?? Intl.defaultLocale),
      name: info.code,
      symbol: info.symbol,
      decimalDigits: info.decimals,
    );
    return formatter.format(_major(money));
  }

  /// Short amount for charts and tight spaces, for example `₹1.2L`.
  static String compact(Money money, {String? locale}) {
    final info = money.info;
    final formatter = NumberFormat.compactCurrency(
      locale: AppLocale.normalize(locale ?? Intl.defaultLocale),
      name: info.code,
      symbol: info.symbol,
      decimalDigits: money.amountMinor.abs() < 1000 * info.minorPerMajor
          ? 0
          : null,
    );
    return formatter.format(_major(money));
  }

  /// Plain number without symbol or grouping, using the locale's decimal
  /// mark, for pre-filling an amount field (`1250.50`, `1250,50`, `1200`).
  /// The result parses back to the same amount with `MoneyParser`.
  static String forInput(Money money, {String? locale}) {
    final info = money.info;
    final symbols = NumberFormat.decimalPattern(
      AppLocale.normalize(locale ?? Intl.defaultLocale),
    ).symbols;
    final absolute = money.amountMinor.abs();
    final sign = money.isNegative ? '-' : '';
    if (info.decimals == 0) return '$sign$absolute';
    final major = absolute ~/ info.minorPerMajor;
    final minor = (absolute % info.minorPerMajor).toString().padLeft(
      info.decimals,
      '0',
    );
    final mark = symbols.DECIMAL_SEP == ',' ? ',' : '.';
    return '$sign$major$mark$minor';
  }

  /// Symbol for [currency], for an input prefix.
  static String symbolOf(String currency) =>
      CurrencyInfo.tryOf(currency)?.symbol ?? currency;

  // Minor units are integers; dividing for display is exact enough because
  // every allowed amount (<= 1e11 minor units) is below 2^53.
  static double _major(Money money) =>
      money.amountMinor / money.info.minorPerMajor;
}
