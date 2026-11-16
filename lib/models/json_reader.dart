import 'money.dart';

/// Marker for "argument not passed" in `copyWith`, so nullable fields can
/// be cleared by passing `null` explicitly.
const Object unset = _Unset();

class _Unset {
  const _Unset();
}

/// Returns [value] unless it is [unset], in which case [current].
T pick<T>(Object? value, T current) =>
    identical(value, unset) ? current : value as T;

/// Strict, cast-safe reader for JSON maps from the server.
///
/// Wrong or missing required values throw a [FormatException] naming the
/// model and field (never the value), which the error mapper reports as an
/// unknown failure. No field silently becomes "now" or a placeholder.
class JsonReader {
  JsonReader(this.json, this.model);

  /// Reads [value] as a JSON object or throws.
  factory JsonReader.of(Object? value, String model) {
    if (value is Map<String, dynamic>) return JsonReader(value, model);
    if (value is Map) {
      return JsonReader(Map<String, dynamic>.from(value), model);
    }
    throw FormatException('$model: expected an object');
  }

  final Map<String, dynamic> json;
  final String model;

  bool has(String key) => json[key] != null;

  Never _bad(String key, String expected) =>
      throw FormatException('$model.$key: expected $expected');

  String string(String key) {
    final value = json[key];
    if (value is String) return value;
    _bad(key, 'string');
  }

  String? optString(String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is String) return value;
    _bad(key, 'string or null');
  }

  /// A string that must not be blank.
  String nonEmpty(String key) {
    final value = string(key);
    if (value.trim().isEmpty) _bad(key, 'non-empty string');
    return value;
  }

  int integer(String key) {
    final value = json[key];
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    _bad(key, 'integer');
  }

  int? optInteger(String key) => json[key] == null ? null : integer(key);

  bool boolean(String key, {bool? fallback}) {
    final value = json[key];
    if (value is bool) return value;
    if (value == null && fallback != null) return fallback;
    _bad(key, 'boolean');
  }

  DateTime instant(String key) {
    final value = json[key];
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    _bad(key, 'timestamp');
  }

  DateTime? optInstant(String key) => json[key] == null ? null : instant(key);

  /// A calendar date (`yyyy-MM-dd`, or a timestamp whose date part is used)
  /// as a UTC midnight value carrying only the date.
  DateTime date(String key) {
    final value = json[key];
    if (value is String && value.length >= 10) {
      final parsed = DateTime.tryParse(value.substring(0, 10));
      if (parsed != null) {
        return DateTime.utc(parsed.year, parsed.month, parsed.day);
      }
    }
    _bad(key, 'date');
  }

  /// Money from an integer minor-unit field and a currency field.
  Money money(String amountKey, {String currencyKey = 'currency'}) {
    final code = string(currencyKey).trim().toUpperCase();
    try {
      return Money(integer(amountKey), code);
    } on ArgumentError {
      _bad(currencyKey, 'supported currency');
    }
  }

  /// One of [values] by its `name`.
  T enumValue<T extends Enum>(String key, List<T> values, {T? fallback}) {
    final raw = json[key];
    if (raw == null && fallback != null) return fallback;
    if (raw is String) {
      for (final value in values) {
        if (value.name == raw) return value;
      }
    }
    _bad(key, 'one of ${values.map((v) => v.name).join('|')}');
  }

  /// A list of objects parsed with [parse]. Missing means empty.
  List<T> objects<T>(String key, T Function(Object? item) parse) {
    final value = json[key];
    if (value == null) return const [];
    if (value is! List) _bad(key, 'list');
    return [for (final item in value) parse(item)];
  }

  /// A nested object, or null.
  Map<String, dynamic>? optObject(String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    _bad(key, 'object');
  }
}

/// Reads a list response (`select()` or a set-returning RPC).
List<T> parseList<T>(
  Object? data,
  T Function(Object? item) parse,
  String model,
) {
  if (data is! List) throw FormatException('$model: expected a list');
  return [for (final item in data) parse(item)];
}
