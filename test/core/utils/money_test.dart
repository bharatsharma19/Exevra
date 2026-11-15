import 'package:expense_manager/core/utils/app_locale.dart';
import 'package:expense_manager/core/utils/money_format.dart';
import 'package:expense_manager/core/utils/money_parser.dart';
import 'package:expense_manager/models/currency_info.dart';
import 'package:expense_manager/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

int parsed(String input, String currency, String locale) {
  final result = MoneyParser.parse(input, currency: currency, locale: locale);
  if (result is MoneyParsed) {
    expect(result.value.currency, currency);
    return result.value.amountMinor;
  }
  fail('Expected "$input" to parse, got ${(result as MoneyParseError).key}');
}

String rejected(String input, String currency, String locale) {
  final result = MoneyParser.parse(input, currency: currency, locale: locale);
  if (result is MoneyParseError) return result.key;
  fail(
    'Expected "$input" to be rejected, got ${(result as MoneyParsed).value}',
  );
}

String nbspFree(String s) => s.replaceAll(' ', ' ').replaceAll(' ', ' ');

void main() {
  group('CurrencyInfo', () {
    test('has the 25 supported currencies with ISO exponents', () {
      expect(CurrencyInfo.all, hasLength(25));
      expect(CurrencyInfo.of('JPY').decimals, 0);
      expect(CurrencyInfo.of('KRW').decimals, 0);
      expect(CurrencyInfo.of('IDR').decimals, 2);
      expect(CurrencyInfo.of('INR').minorPerMajor, 100);
      expect(CurrencyInfo.isSupported('XYZ'), isFalse);
      expect(() => CurrencyInfo.of('XYZ'), throwsArgumentError);
    });
  });

  group('Money', () {
    test('integer arithmetic in one currency', () {
      final a = Money(1050, 'INR');
      final b = Money(250, 'INR');
      expect(a + b, Money(1300, 'INR'));
      expect(a - b, Money(800, 'INR'));
      expect((b - a).isNegative, isTrue);
      expect(Money.sum([a, b, b], 'INR').amountMinor, 1550);
      expect(a > b, isTrue);
    });

    test('mixing currencies throws', () {
      expect(() => Money(1, 'INR') + Money(1, 'USD'), throwsArgumentError);
      expect(() => Money.sum([Money(1, 'USD')], 'INR'), throwsArgumentError);
      expect(() => Money(1, 'ABC'), throwsArgumentError);
    });

    test('debug string', () {
      expect(Money(125050, 'INR').toString(), 'INR 1250.50');
      expect(Money(-5, 'USD').toString(), 'USD -0.05');
      expect(Money(1200, 'JPY').toString(), 'JPY 1200');
    });
  });

  group('MoneyParser', () {
    test('en_IN lakh grouping', () {
      expect(parsed('1,23,456.78', 'INR', 'en_IN'), 12345678);
      expect(parsed('₹ 1,250.50', 'INR', 'en_IN'), 125050);
      expect(parsed('1250', 'INR', 'en-IN'), 125000);
    });

    test('de_DE comma decimal', () {
      expect(parsed('1.234,56', 'EUR', 'de_DE'), 123456);
      expect(parsed('12,50', 'EUR', 'de_DE'), 1250);
      expect(parsed('1.234', 'EUR', 'de_DE'), 123400);
      expect(parsed('1 234,5', 'EUR', 'fr_FR'), 123450);
    });

    test('comma decimal accepted in en_US when unambiguous', () {
      expect(parsed('12,5', 'USD', 'en_US'), 1250);
      expect(parsed('12,50', 'USD', 'en_US'), 1250);
      expect(parsed('1,234', 'USD', 'en_US'), 123400);
      expect(parsed('1,234,567.89', 'USD', 'en_US'), 123456789);
      expect(parsed('.5', 'USD', 'en_US'), 50);
    });

    test('JPY has no decimals', () {
      expect(parsed('1200', 'JPY', 'ja_JP'), 1200);
      expect(parsed('1,200', 'JPY', 'en_US'), 1200);
      expect(rejected('12.5', 'JPY', 'en_US'), 'amount_too_many_decimals');
    });

    test('rejects too many decimals', () {
      expect(rejected('12.345', 'INR', 'en_IN'), 'amount_too_many_decimals');
      expect(rejected('1,005', 'EUR', 'de_DE'), 'amount_too_many_decimals');
    });

    test('rejects amounts above the maximum', () {
      expect(parsed('1000000000', 'INR', 'en_IN'), Money.maxAmountMinor);
      expect(rejected('1000000000.01', 'INR', 'en_IN'), 'amount_too_large');
      expect(
        rejected('99999999999999999999', 'INR', 'en_IN'),
        'amount_too_large',
      );
      expect(parsed('100000000000', 'JPY', 'ja_JP'), Money.maxAmountMinor);
      expect(rejected('100000000001', 'JPY', 'ja_JP'), 'amount_too_large');
    });

    test('rejects zero, negatives, blanks and junk', () {
      expect(rejected('0', 'INR', 'en_IN'), 'amount_not_positive');
      expect(rejected('0.00', 'INR', 'en_IN'), 'amount_not_positive');
      expect(rejected('-5', 'INR', 'en_IN'), 'amount_not_positive');
      expect(rejected('   ', 'INR', 'en_IN'), 'amount_required');
      expect(rejected('12a', 'INR', 'en_IN'), 'amount_invalid');
      expect(rejected('1,,2', 'INR', 'en_IN'), 'amount_invalid');
      expect(rejected('1.2.3,4', 'INR', 'en_IN'), 'amount_invalid');
      expect(rejected('.', 'INR', 'en_IN'), 'amount_invalid');
    });

    test('failure is a validation failure for the amount field', () {
      final result = MoneyParser.parse('-1', currency: 'INR', locale: 'en_IN');
      expect(result, isA<MoneyParseError>());
      final failure = (result as MoneyParseError).failure;
      expect(failure.key, 'amount_not_positive');
    });
  });

  group('MoneyFormat', () {
    test('en_IN uses lakh grouping', () {
      expect(
        MoneyFormat.format(Money(12345678, 'INR'), locale: 'en_IN'),
        '₹1,23,456.78',
      );
      expect(
        MoneyFormat.format(Money(125050, 'INR'), locale: 'en-IN'),
        '₹1,250.50',
      );
    });

    test('per-currency decimals', () {
      expect(MoneyFormat.format(Money(1200, 'JPY'), locale: 'en_US'), '¥1,200');
      expect(
        MoneyFormat.format(Money(99999, 'USD'), locale: 'en_US'),
        r'$999.99',
      );
    });

    test('de_DE places the symbol after the number', () {
      expect(
        nbspFree(MoneyFormat.format(Money(123456, 'EUR'), locale: 'de_DE')),
        '1.234,56 €',
      );
    });

    test('negative amounts keep the sign', () {
      expect(
        MoneyFormat.format(Money(-1050, 'USD'), locale: 'en_US'),
        r'-$10.50',
      );
    });

    test('forInput round-trips through the parser', () {
      for (final (money, locale) in [
        (Money(125050, 'INR'), 'en_IN'),
        (Money(123456, 'EUR'), 'de_DE'),
        (Money(1200, 'JPY'), 'ja_JP'),
        (Money(5, 'USD'), 'en_US'),
      ]) {
        final text = MoneyFormat.forInput(money, locale: locale);
        expect(parsed(text, money.currency, locale), money.amountMinor);
      }
    });

    test('compact', () {
      expect(
        MoneyFormat.compact(Money(85000, 'USD'), locale: 'en_US'),
        r'$850',
      );
      expect(
        MoneyFormat.compact(Money(450000, 'USD'), locale: 'en_US'),
        r'$4.5K',
      );
    });
  });

  group('AppLocale', () {
    test('normalises tags and falls back to en_IN', () {
      expect(AppLocale.normalize('en-IN'), 'en_IN');
      expect(AppLocale.normalize('de'), 'de');
      expect(AppLocale.normalize(null), 'en_IN');
      expect(AppLocale.normalize('zz-ZZ'), 'en_IN');
    });

    test('currency follows the locale region when supported', () {
      expect(AppLocale.currencyFor('en-IN'), 'INR');
      expect(AppLocale.currencyFor('en-US'), 'USD');
      expect(AppLocale.currencyFor('de-DE'), 'EUR');
      expect(AppLocale.currencyFor('ja-JP'), 'JPY');
      expect(AppLocale.currencyFor(null), 'INR');
    });
  });
}
