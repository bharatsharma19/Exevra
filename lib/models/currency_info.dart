/// A currency the app supports: ISO 4217 code, minor-unit exponent,
/// display symbol and English name.
///
/// The list matches `public.supported_currency_codes()` on the server.
class CurrencyInfo {
  const CurrencyInfo({
    required this.code,
    required this.decimals,
    required this.symbol,
    required this.name,
  });

  final String code;

  /// Number of minor-unit digits (ISO 4217 exponent): 2 for most, 0 for
  /// JPY and KRW.
  final int decimals;

  final String symbol;
  final String name;

  /// 10 ^ [decimals]: how many minor units make one major unit.
  int get minorPerMajor {
    var factor = 1;
    for (var i = 0; i < decimals; i++) {
      factor *= 10;
    }
    return factor;
  }

  /// Fallback currency when nothing else is known (India-first launch).
  static const String fallbackCode = 'INR';

  /// Every supported currency, in the order shown in pickers.
  static const List<CurrencyInfo> all = [
    CurrencyInfo(code: 'INR', decimals: 2, symbol: '₹', name: 'Indian Rupee'),
    CurrencyInfo(code: 'USD', decimals: 2, symbol: r'$', name: 'US Dollar'),
    CurrencyInfo(code: 'EUR', decimals: 2, symbol: '€', name: 'Euro'),
    CurrencyInfo(code: 'GBP', decimals: 2, symbol: '£', name: 'British Pound'),
    CurrencyInfo(code: 'AED', decimals: 2, symbol: 'AED', name: 'UAE Dirham'),
    CurrencyInfo(
      code: 'SGD',
      decimals: 2,
      symbol: r'S$',
      name: 'Singapore Dollar',
    ),
    CurrencyInfo(
      code: 'AUD',
      decimals: 2,
      symbol: r'A$',
      name: 'Australian Dollar',
    ),
    CurrencyInfo(
      code: 'CAD',
      decimals: 2,
      symbol: r'C$',
      name: 'Canadian Dollar',
    ),
    CurrencyInfo(code: 'JPY', decimals: 0, symbol: '¥', name: 'Japanese Yen'),
    CurrencyInfo(code: 'CHF', decimals: 2, symbol: 'CHF', name: 'Swiss Franc'),
    CurrencyInfo(code: 'CNY', decimals: 2, symbol: 'CN¥', name: 'Chinese Yuan'),
    CurrencyInfo(
      code: 'NZD',
      decimals: 2,
      symbol: r'NZ$',
      name: 'New Zealand Dollar',
    ),
    CurrencyInfo(
      code: 'ZAR',
      decimals: 2,
      symbol: 'R',
      name: 'South African Rand',
    ),
    CurrencyInfo(code: 'SEK', decimals: 2, symbol: 'kr', name: 'Swedish Krona'),
    CurrencyInfo(
      code: 'NOK',
      decimals: 2,
      symbol: 'kr',
      name: 'Norwegian Krone',
    ),
    CurrencyInfo(code: 'DKK', decimals: 2, symbol: 'kr', name: 'Danish Krone'),
    CurrencyInfo(
      code: 'HKD',
      decimals: 2,
      symbol: r'HK$',
      name: 'Hong Kong Dollar',
    ),
    CurrencyInfo(code: 'SAR', decimals: 2, symbol: 'SAR', name: 'Saudi Riyal'),
    CurrencyInfo(
      code: 'MYR',
      decimals: 2,
      symbol: 'RM',
      name: 'Malaysian Ringgit',
    ),
    CurrencyInfo(code: 'THB', decimals: 2, symbol: '฿', name: 'Thai Baht'),
    CurrencyInfo(
      code: 'IDR',
      decimals: 2,
      symbol: 'Rp',
      name: 'Indonesian Rupiah',
    ),
    CurrencyInfo(
      code: 'PHP',
      decimals: 2,
      symbol: '₱',
      name: 'Philippine Peso',
    ),
    CurrencyInfo(
      code: 'BRL',
      decimals: 2,
      symbol: r'R$',
      name: 'Brazilian Real',
    ),
    CurrencyInfo(
      code: 'MXN',
      decimals: 2,
      symbol: r'MX$',
      name: 'Mexican Peso',
    ),
    CurrencyInfo(
      code: 'KRW',
      decimals: 0,
      symbol: '₩',
      name: 'South Korean Won',
    ),
  ];

  static final Map<String, CurrencyInfo> _byCode = {
    for (final c in all) c.code: c,
  };

  /// Whether [code] is a supported ISO code (upper-case, exact).
  static bool isSupported(String? code) => _byCode.containsKey(code);

  /// The currency for [code]. Throws [ArgumentError] when unsupported.
  static CurrencyInfo of(String code) {
    final info = _byCode[code];
    if (info == null) {
      throw ArgumentError.value(code, 'code', 'Unsupported currency');
    }
    return info;
  }

  /// The currency for [code], or null when unsupported.
  static CurrencyInfo? tryOf(String? code) =>
      code == null ? null : _byCode[code];

  @override
  bool operator ==(Object other) => other is CurrencyInfo && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code;
}
