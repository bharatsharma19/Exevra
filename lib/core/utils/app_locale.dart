import 'dart:ui' show Locale, PlatformDispatcher;

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
  static String initFromDevice() {
    final device = PlatformDispatcher.instance.locale;
    Intl.defaultLocale = normalize(device.toLanguageTag());
    return toBcp47(device);
  }

  /// `en-IN` style tag for [locale], as stored in `profiles.locale`.
  static String toBcp47(Locale locale) {
    final country = locale.countryCode;
    return country == null || country.isEmpty
        ? locale.languageCode
        : '${locale.languageCode}-$country';
  }

  /// The supported currency of [localeTag]'s region, else INR.
  static String currencyFor(String? localeTag) {
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
}
