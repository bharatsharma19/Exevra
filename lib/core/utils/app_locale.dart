import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../../models/currency_info.dart';

/// Locale helpers. The app formats numbers and dates with the device
/// locale; India (en_IN, INR) is the fallback.
abstract final class AppLocale {
  /// Locale used when the device locale is unknown to intl.
  static const String fallback = 'en_IN';

  /// Normalises a BCP-47 or intl tag (`en-IN`, `en_IN`, `de`) to the intl
  /// form intl's number data knows, or [fallback].
  static String normalize(String? tag) {
    if (tag == null || tag.trim().isEmpty) return fallback;
    final cleaned = tag.trim().replaceAll('-', '_');
    return Intl.verifiedLocale(
          cleaned,
          NumberFormat.localeExists,
          onFailure: (_) => fallback,
        ) ??
        fallback;
  }

  /// The intl locale currently used for formatting.
  static String get current => normalize(Intl.defaultLocale);

  /// Reads the device locale and makes it the default for intl.
  /// Returns the BCP-47 tag (for example `en-IN`) to store on the profile.
  static Future<String> initFromDevice() async {
    final device = PlatformDispatcher.instance.locale;
    await useLocale(device.toLanguageTag());
    return toBcp47(device);
  }

  /// Loads intl's date symbols and makes [tag] (or [fallback] when intl
  /// has no number or date data for it) the default locale.
  ///
  /// Every `DateFormat` built without an explicit locale uses the default,
  /// and throws `LocaleDataException` for any locale other than `en_US`
  /// until its date symbols are loaded, so this runs before the first
  /// frame.
  static Future<String> useLocale(String? tag) async {
    await initializeDateFormatting();
    final number = normalize(tag);
    final locale = DateFormat.localeExists(number)
        ? number
        : Intl.verifiedLocale(
                number,
                DateFormat.localeExists,
                onFailure: (_) => fallback,
              ) ??
              fallback;
    Intl.defaultLocale = locale;
    return locale;
  }

  /// `en-IN` style tag for [locale], as stored in `profiles.locale`.
  static String toBcp47(Locale locale) {
    final country = locale.countryCode;
    return country == null || country.isEmpty
        ? locale.languageCode
        : '${locale.languageCode}-$country';
  }

  /// The supported currency of [localeTag]'s region, else INR.
  ///
  /// The region decides (`ar-AE` and `en-AE` are both AED); intl's locale
  /// data is only asked when the tag has no region, because it has no
  /// data for many regional tags and would answer for the bare language.
  static String currencyFor(String? localeTag) {
    final region = regionOf(localeTag);
    if (region != null) {
      return _currencyByRegion[region] ?? CurrencyInfo.fallbackCode;
    }
    if (localeTag == null || localeTag.trim().isEmpty) {
      return CurrencyInfo.fallbackCode;
    }
    try {
      final code = NumberFormat.simpleCurrency(
        locale: normalize(localeTag),
      ).currencyName;
      if (CurrencyInfo.isSupported(code)) return code!;
    } on Object {
      // Unknown locale data: fall through to the default.
    }
    return CurrencyInfo.fallbackCode;
  }

  /// The upper-case region of a BCP-47 or intl tag (`en-IN`, `zh_Hant_HK`,
  /// `es-419`), or null when it has none.
  static String? regionOf(String? tag) {
    if (tag == null) return null;
    final parts = tag.trim().split(RegExp('[-_]'));
    // The first subtag is the language; a script (4 letters) may follow.
    for (final part in parts.skip(1)) {
      if (RegExp(r'^[A-Za-z]{2}$').hasMatch(part)) return part.toUpperCase();
      if (RegExp(r'^[0-9]{3}$').hasMatch(part)) return part;
      if (part.length != 4) return null;
    }
    return null;
  }

  /// Regions (ISO 3166 codes) whose everyday currency is a supported one.
  @visibleForTesting
  static const Map<String, String> regionsByCurrency = {
    'INR': 'IN',
    'USD': 'US PR GU VI AS MP UM EC SV TL FM MH PW BQ TC VG IO',
    'EUR':
        'AT BE HR CY EE FI FR DE GR IE IT LV LT LU MT NL PT SK SI ES AD MC '
        'SM VA ME XK AX GF GP MQ YT RE PM BL MF',
    'GBP': 'GB IM JE GG',
    'AED': 'AE',
    'SGD': 'SG',
    'AUD': 'AU CX CC NF KI NR TV',
    'CAD': 'CA',
    'JPY': 'JP',
    'CHF': 'CH LI',
    'CNY': 'CN',
    'NZD': 'NZ CK NU PN TK',
    'ZAR': 'ZA',
    'SEK': 'SE',
    'NOK': 'NO SJ BV',
    'DKK': 'DK FO GL',
    'HKD': 'HK',
    'SAR': 'SA',
    'MYR': 'MY',
    'THB': 'TH',
    'IDR': 'ID',
    'PHP': 'PH',
    'BRL': 'BR',
    'MXN': 'MX',
    'KRW': 'KR',
  };

  static final Map<String, String> _currencyByRegion = {
    for (final entry in regionsByCurrency.entries)
      for (final region in entry.value.split(' ')) region: entry.key,
  };
}
