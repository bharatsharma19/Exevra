import 'package:flutter/foundation.dart';

/// Minimal app logger.
///
/// * Release builds log nothing.
/// * Messages and errors are passed through [redact] so tokens, email
///   addresses, phone numbers and URL query strings never reach the log.
/// * Callers must not pass request bodies or user content; log what
///   happened, not the data involved.
abstract final class AppLogger {
  static void debug(String message) => _write('DEBUG', message);

  static void info(String message) => _write('INFO', message);

  static void warn(String message, [Object? error]) =>
      _write('WARN', message, error);

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _write('ERROR', message, error);
    if (!kReleaseMode && stackTrace != null) {
      debugPrint(redact(stackTrace.toString()));
    }
  }

  static void _write(String level, String message, [Object? error]) {
    if (kReleaseMode) return;
    final buffer = StringBuffer('[$level] ')..write(redact(message));
    if (error != null) {
      buffer
        ..write(' | ')
        ..write(redact(error.toString()));
    }
    debugPrint(buffer.toString());
  }

  static final List<(RegExp, String)> _rules = [
    // JWTs and other dotted base64url tokens.
    (
      RegExp(r'eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*'),
      '<token>',
    ),
    // Authorization header values.
    (RegExp(r'(Bearer|Basic)\s+[^\s,;]+', caseSensitive: false), r'$1 <token>'),
    // Supabase / provider style keys.
    (RegExp(r'\b(sb_(publishable|secret)_|sk-)[A-Za-z0-9_-]+'), '<key>'),
    // Query strings (may carry tokens or emails); keep the path only.
    (RegExp(r'\?[^\s#]*'), '?<redacted>'),
    // Email addresses.
    (RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'), '<email>'),
    // Phone numbers: optional +, then 8 or more digits with separators.
    (RegExp(r'\+?\d[\d\s().-]{6,}\d'), '<number>'),
    // key=value or "key": "value" pairs for sensitive names.
    (
      RegExp(
        r'''(token|access_token|refresh_token|password|apikey|api_key|secret|authorization)(["']?\s*[:=]\s*["']?)[^\s"',&]+''',
        caseSensitive: false,
      ),
      r'$1$2<redacted>',
    ),
  ];

  /// Removes tokens, keys, email addresses, phone numbers and query
  /// strings from [input].
  static String redact(String input) {
    var output = input;
    for (final (pattern, replacement) in _rules) {
      output = output.replaceAllMapped(pattern, (match) {
        return replacement.replaceAllMapped(RegExp(r'\$(\d)'), (ref) {
          final group = int.parse(ref.group(1)!);
          return group <= match.groupCount ? (match.group(group) ?? '') : '';
        });
      });
    }
    return output;
  }
}
