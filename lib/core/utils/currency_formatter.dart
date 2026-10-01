import 'package:intl/intl.dart';
import '../constants/app_constants.dart';

/// Formatter for financial values, amounts, and currency symbols
class CurrencyFormatter {
  CurrencyFormatter._();

  static String format(
    double amount, {
    String currencyCode = AppConstants.defaultCurrency,
    bool showDecimals = true,
  }) {
    final symbol = AppConstants.currencies[currencyCode] ?? '₹';
    final formatter = NumberFormat.currency(
      symbol: symbol,
      decimalDigits: showDecimals ? 2 : 0,
    );
    return formatter.format(amount);
  }

  static String formatCompact(
    double amount, {
    String currencyCode = AppConstants.defaultCurrency,
  }) {
    final symbol = AppConstants.currencies[currencyCode] ?? '₹';
    if (currencyCode == 'INR') {
      if (amount >= 10000000) {
        return '$symbol${(amount / 10000000).toStringAsFixed(1)}Cr';
      } else if (amount >= 100000) {
        return '$symbol${(amount / 100000).toStringAsFixed(1)}L';
      } else if (amount >= 1000) {
        return '$symbol${(amount / 1000).toStringAsFixed(1)}k';
      } else {
        return '$symbol${amount.toStringAsFixed(0)}';
      }
    } else {
      if (amount >= 1000000) {
        return '$symbol${(amount / 1000000).toStringAsFixed(1)}M';
      } else if (amount >= 1000) {
        return '$symbol${(amount / 1000).toStringAsFixed(1)}k';
      } else {
        return '$symbol${amount.toStringAsFixed(0)}';
      }
    }
  }

  static double? parseAmount(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleaned);
  }
}
