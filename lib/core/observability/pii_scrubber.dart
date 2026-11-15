import 'package:sentry_flutter/sentry_flutter.dart';

/// Removes personal data and credentials from crash reports before they
/// leave the device.
///
/// Used as Sentry's `beforeSend` and `beforeBreadcrumb` callbacks. The rules
/// are deliberately broad: a report that loses some context is better than
/// one that carries an email address or a session token.
abstract final class PiiScrubber {
  /// Replacement for removed values.
  static const String filtered = '[Filtered]';

  /// `beforeSend` callback: scrubs [event] in place and returns it.
  static SentryEvent scrubEvent(SentryEvent event, Hint hint) {
    final user = event.user;
    if (user != null) {
      // Keep only the opaque account id; drop email, username, name, IP
      // address, location and custom data.
      event.user = user.id == null ? null : SentryUser(id: user.id);
    }

    final request = event.request;
    if (request != null) {
      // Drop the body, cookies, headers, environment, query and fragment.
      final url = request.url;
      event.request = SentryRequest(
        url: url == null ? null : stripQuery(url),
        method: request.method,
      );
    }

    final message = event.message;
    if (message != null) {
      event.message = SentryMessage(
        scrubText(message.formatted),
        template: message.template == null
            ? null
            : scrubText(message.template!),
        params: message.params == null
            ? null
            : [for (final param in message.params!) _scrubValue(param)],
      );
    }

    for (final exception in event.exceptions ?? const <SentryException>[]) {
      final value = exception.value;
      if (value != null) exception.value = scrubText(value);
    }

    final transaction = event.transaction;
    if (transaction != null) event.transaction = scrubText(transaction);

    final tags = event.tags;
    if (tags != null) {
      event.tags = {
        for (final entry in tags.entries)
          if (!isSensitiveKey(entry.key)) entry.key: scrubText(entry.value),
      };
    }

    // `extra` is deprecated in favour of contexts, but plugins and older
    // call sites may still fill it, so it must be scrubbed too.
    // ignore: deprecated_member_use
    final extra = event.extra;
    if (extra != null) {
      // ignore: deprecated_member_use
      event.extra = scrubMap(extra);
    }

    _scrubContexts(event.contexts);

    final breadcrumbs = event.breadcrumbs;
    if (breadcrumbs != null) {
      event.breadcrumbs = [
        for (final crumb in breadcrumbs) ?scrubBreadcrumb(crumb, Hint()),
      ];
    }

    return event;
  }

  /// `beforeBreadcrumb` callback: scrubs [breadcrumb] in place.
  static Breadcrumb? scrubBreadcrumb(Breadcrumb? breadcrumb, Hint hint) {
    if (breadcrumb == null) return null;
    final message = breadcrumb.message;
    if (message != null) breadcrumb.message = scrubText(message);
    final data = breadcrumb.data;
    if (data != null) breadcrumb.data = scrubMap(data);
    return breadcrumb;
  }

  static void _scrubContexts(Contexts contexts) {
    // The device name is often the owner's name ("Asha's phone").
    contexts.device?.name = null;
    for (final key in contexts.keys.toList()) {
      if (isSensitiveKey(key)) {
        contexts.remove(key);
        continue;
      }
      final value = contexts[key];
      if (value is Map || value is String || value is List) {
        contexts[key] = _scrubValue(value);
      }
    }
  }

  /// Returns a copy of [map] without sensitive keys and with every string
  /// value scrubbed, recursively.
  static Map<String, dynamic> scrubMap(Map<dynamic, dynamic> map) {
    return {
      for (final entry in map.entries)
        if (!isSensitiveKey('${entry.key}'))
          '${entry.key}': _isUrlKey('${entry.key}') && entry.value is String
              ? stripQuery(entry.value as String)
              : _scrubValue(entry.value),
    };
  }

  static Object? _scrubValue(Object? value) {
    return switch (value) {
      final String text => scrubText(text),
      final Map<dynamic, dynamic> map => scrubMap(map),
      final List<dynamic> list => [for (final item in list) _scrubValue(item)],
      _ => value,
    };
  }

  /// Whether a map key names a value that must never be reported.
  static bool isSensitiveKey(String key) {
    final normalized = key
        .replaceAllMapped(
          RegExp('([a-z0-9])([A-Z])'),
          (m) => '${m.group(1)}_${m.group(2)}',
        )
        .toLowerCase();
    if (_droppedKeys.contains(normalized)) return true;
    final parts = normalized.split(RegExp('[^a-z0-9]+'));
    return parts.any(_sensitiveKeyParts.contains) ||
        normalized.contains('api_key') ||
        normalized.contains('access_key') ||
        normalized.contains('private_key');
  }

  static const Set<String> _sensitiveKeyParts = {
    'apikey',
    'auth',
    'authorization',
    'bearer',
    'cookie',
    'cookies',
    'credential',
    'credentials',
    'email',
    'emails',
    'ip',
    'jwt',
    'otp',
    'passcode',
    'passwd',
    'password',
    'phone',
    'pin',
    'secret',
    'session',
    'token',
    'tokens',
    'username',
  };

  /// Keys that carry URL parts which may hold tokens (Sentry's HTTP
  /// breadcrumbs use the dotted names).
  static const Set<String> _droppedKeys = {
    'http.query',
    'http.fragment',
    'query',
    'query_string',
    'fragment',
  };

  static bool _isUrlKey(String key) {
    final lower = key.toLowerCase();
    return lower == 'url' || lower.endsWith('.url') || lower.endsWith('_url');
  }

  /// Removes the query string and fragment from a URL or URL-like string.
  static String stripQuery(String url) {
    final cut = url.indexOf(RegExp('[?#]'));
    return scrubText(cut < 0 ? url : url.substring(0, cut));
  }

  static final List<(RegExp, String)> _rules = [
    // JWTs (Supabase access tokens and similar).
    (RegExp(r'eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*'), '[jwt]'),
    // Authorization header values.
    (
      RegExp(r'\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
      r'$1 [token]',
    ),
    // Supabase keys (sb_publishable_, sb_secret_, ...) and sk- style keys.
    (RegExp(r'\bsb_[a-z]+_[A-Za-z0-9_-]+'), '[key]'),
    (RegExp(r'\bsk-[A-Za-z0-9_-]{8,}'), '[key]'),
    // Query strings of absolute URLs (any scheme), up to whitespace.
    (RegExp(r'\b([a-z][a-z0-9+.-]*://[^\s?#]*)[?#][^\s]*'), r'$1'),
    // Query strings of app routes and relative paths ("/invite?token=...").
    (RegExp(r'(?<![\w:/.])(/[^\s?#]*)[?#]\S*'), r'$1'),
    // Email addresses.
    (RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'), '[email]'),
    // International phone numbers.
    (RegExp(r'\+\d[\d ()-]{7,}\d'), '[phone]'),
    // key=value or "key": "value" pairs with sensitive names.
    (
      RegExp(
        r'''\b(access_token|refresh_token|token|password|apikey|api_key|secret|authorization)(["']?\s*[:=]\s*["']?)[^\s"',&]+''',
        caseSensitive: false,
      ),
      r'$1$2[Filtered]',
    ),
  ];

  /// Replaces emails, JWTs, keys, bearer tokens, phone numbers and URL
  /// query strings in [input].
  static String scrubText(String input) {
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
