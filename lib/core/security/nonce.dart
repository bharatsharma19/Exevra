import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Nonces for Sign in with Apple.
///
/// Apple receives the SHA-256 hash of a random nonce and embeds it in the
/// identity token; Supabase receives the raw nonce and checks that its hash
/// matches the token, so a token captured elsewhere cannot be replayed.
abstract final class Nonce {
  static const String _charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';

  /// A random nonce of [length] characters from a secure source.
  static String generate([int length = 32, Random? random]) {
    if (length < 16) throw ArgumentError.value(length, 'length', 'min 16');
    final source = random ?? Random.secure();
    return List.generate(
      length,
      (_) => _charset[source.nextInt(_charset.length)],
    ).join();
  }

  /// Lower-case hex SHA-256 of [input] (UTF-8).
  static String sha256Hex(String input) =>
      sha256.convert(utf8.encode(input)).toString();
}
