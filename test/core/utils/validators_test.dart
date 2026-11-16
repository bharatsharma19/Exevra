import 'package:expense_manager/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('email', () {
    test('accepts real-world addresses', () {
      for (final email in [
        'user@example.com',
        'first+tag@example.co.in',
        'a.b-c_d@mail.sub.example.org',
        'someone@example.travel',
        'x@example.photography',
        '  padded@example.com  ',
      ]) {
        expect(Validators.validateEmail(email), isNull, reason: email);
      }
    });

    test('rejects malformed addresses', () {
      for (final email in [
        'invalid-email',
        'no-at.example.com',
        'two@@example.com',
        'user@localhost',
        'user@example.c',
        'user name@example.com',
        '@example.com',
      ]) {
        expect(Validators.validateEmail(email), isNotNull, reason: email);
      }
      expect(Validators.validateEmail(''), 'Email address is required');
      expect(Validators.validateEmail(null), 'Email address is required');
    });
  });

  test('sign-in accepts any existing password', () {
    expect(Validators.validateLoginPassword('weak'), isNull);
    expect(Validators.validateLoginPassword('12345678'), isNull);
    expect(Validators.validateLoginPassword(''), 'Password is required');
  });

  test('new passwords follow the server policy', () {
    expect(Validators.validateNewPassword('Passw0rdX'), isNull);
    expect(Validators.validateNewPassword('Sh0rt'), contains('8 characters'));
    expect(Validators.validateNewPassword('password1'), contains('upper-case'));
    expect(Validators.validateNewPassword('PASSWORD1'), contains('lower-case'));
    expect(Validators.validateNewPassword('Password'), contains('number'));
    expect(Validators.validateNewPassword(''), 'Password is required');
  });

  test('confirmation must match', () {
    final confirm = Validators.confirmPassword(() => 'Passw0rdX');
    expect(confirm('Passw0rdX'), isNull);
    expect(confirm('other'), isNotNull);
  });

  test('display names are 1 to 60 characters', () {
    expect(Validators.validateDisplayName('Ada'), isNull);
    expect(Validators.validateDisplayName('  '), isNotNull);
    expect(Validators.validateDisplayName('x' * 61), isNotNull);
  });

  test('codes are exactly 8 digits', () {
    expect(Validators.validateOtp('12345678'), isNull);
    expect(Validators.validateOtp('123456'), isNotNull);
    expect(Validators.validateOtp('abcdefgh'), isNotNull);
  });
}
