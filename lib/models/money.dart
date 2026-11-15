import 'currency_info.dart';

/// An amount of money in integer minor units of one currency.
///
/// All arithmetic stays on integers; there is no floating point anywhere
/// in money math. Mixing currencies throws an [ArgumentError].
class Money implements Comparable<Money> {
  /// Creates an amount. [currency] must be a supported ISO code.
  Money(this.amountMinor, this.currency) {
    if (!CurrencyInfo.isSupported(currency)) {
      throw ArgumentError.value(currency, 'currency', 'Unsupported currency');
    }
  }

  /// Zero in [currency].
  factory Money.zero(String currency) => Money(0, currency);

  /// Largest single amount the server accepts, in minor units.
  static const int maxAmountMinor = 100000000000;

  final int amountMinor;
  final String currency;

  CurrencyInfo get info => CurrencyInfo.of(currency);

  bool get isZero => amountMinor == 0;
  bool get isNegative => amountMinor < 0;
  bool get isPositive => amountMinor > 0;

  Money operator +(Money other) {
    _requireSameCurrency(other);
    return Money(amountMinor + other.amountMinor, currency);
  }

  Money operator -(Money other) {
    _requireSameCurrency(other);
    return Money(amountMinor - other.amountMinor, currency);
  }

  Money operator -() => Money(-amountMinor, currency);

  Money abs() => isNegative ? -this : this;

  /// Sums [items] in [currency]. Every item must be in [currency].
  static Money sum(Iterable<Money> items, String currency) {
    var total = 0;
    for (final item in items) {
      if (item.currency != currency) {
        throw ArgumentError('Cannot add ${item.currency} to $currency');
      }
      total += item.amountMinor;
    }
    return Money(total, currency);
  }

  void _requireSameCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError('Cannot combine $currency with ${other.currency}');
    }
  }

  @override
  int compareTo(Money other) {
    _requireSameCurrency(other);
    return amountMinor.compareTo(other.amountMinor);
  }

  bool operator <(Money other) => compareTo(other) < 0;
  bool operator >(Money other) => compareTo(other) > 0;
  bool operator <=(Money other) => compareTo(other) <= 0;
  bool operator >=(Money other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.amountMinor == amountMinor &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(amountMinor, currency);

  /// Debug form such as `INR 1250.50`. Use `MoneyFormat` for display.
  @override
  String toString() {
    final d = info.decimals;
    final sign = amountMinor < 0 ? '-' : '';
    final absolute = amountMinor.abs();
    if (d == 0) return '$currency $sign$absolute';
    final factor = info.minorPerMajor;
    final major = absolute ~/ factor;
    final minor = (absolute % factor).toString().padLeft(d, '0');
    return '$currency $sign$major.$minor';
  }
}
