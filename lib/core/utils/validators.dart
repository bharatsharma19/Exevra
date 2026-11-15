import '../errors/failure_messages.dart';

/// Form validators. They return user-facing copy or null.
class Validators {
  Validators._();

  // Deliberately permissive (plus addressing, subdomains, long TLDs); the
  // server validates the address for real.
  static final RegExp _email = RegExp(
    r'^[^\s@]+@[^\s@.]+(\.[^\s@.]+)*\.[^\s@.]{2,}$',
  );

  static String? validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email address is required';
    if (email.length > 254 || !_email.hasMatch(email)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  /// Sign-in only checks that a password was typed: older accounts may
  /// predate the current rules.
  static String? validateLoginPassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    return null;
  }

  /// Rules for a new password; they match the server policy (8+
  /// characters with upper and lower case letters and a digit).
  static String? validateNewPassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) {
      return 'Password must be at least 8 characters long';
    }
    if (value.length > 72) {
      return 'Password must be at most 72 characters long';
    }
    if (!value.contains(RegExp('[a-z]'))) {
      return 'Password must contain a lower-case letter';
    }
    if (!value.contains(RegExp('[A-Z]'))) {
      return 'Password must contain an upper-case letter';
    }
    if (!value.contains(RegExp('[0-9]'))) {
      return 'Password must contain a number';
    }
    return null;
  }

  /// Confirmation field for [password].
  static String? Function(String?) confirmPassword(
    String Function() password,
  ) =>
      (value) => value == password()
      ? null
      : friendlyMessageForKey('password_mismatch');

  static String? validateDisplayName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Name is required';
    if (name.length > 60) return 'Names must be 1 to 60 characters.';
    return null;
  }

  static String? validateOtp(String? value) {
    final code = value?.trim() ?? '';
    if (code.isEmpty) return 'Verification code is required';
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      return 'Please enter a 6-digit code';
    }
    return null;
  }

  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }
}
