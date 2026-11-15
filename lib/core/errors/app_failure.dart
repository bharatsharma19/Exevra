import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logging/app_logger.dart';

/// A failure the app knows how to explain to the user.
///
/// Every repository method throws an [AppFailure] (never a raw backend
/// exception), so notifiers and screens only deal with this closed set.
/// Turn one into copy with `friendlyMessage` in `failure_messages.dart`.
///
/// [key] carries the stable message key from the backend (for example
/// `invite_expired` or `not_group_admin`) when there is one, so the copy can
/// be specific without the UI parsing error strings.
sealed class AppFailure implements Exception {
  const AppFailure({this.key});

  const factory AppFailure.network({String? key}) = NetworkFailure;
  const factory AppFailure.offline() = OfflineFailure;
  const factory AppFailure.timeout() = TimeoutFailure;
  const factory AppFailure.permissionDenied({String? key}) =
      PermissionDeniedFailure;
  const factory AppFailure.notFound({String? key}) = NotFoundFailure;
  const factory AppFailure.validation({String? field, String? key}) =
      ValidationFailure;
  const factory AppFailure.conflict({String? key}) = ConflictFailure;
  const factory AppFailure.rateLimited({DateTime? retryAfter}) =
      RateLimitedFailure;
  const factory AppFailure.quotaExceeded() = QuotaExceededFailure;
  const factory AppFailure.sessionExpired() = SessionExpiredFailure;
  const factory AppFailure.emailNotConfirmed() = EmailNotConfirmedFailure;
  const factory AppFailure.invalidCredentials() = InvalidCredentialsFailure;
  const factory AppFailure.accountExists() = AccountExistsFailure;
  const factory AppFailure.weakPassword({List<String> reasons}) =
      WeakPasswordFailure;
  const factory AppFailure.codeExpired() = CodeExpiredFailure;
  const factory AppFailure.business(String key) = BusinessFailure;
  const factory AppFailure.unknown() = UnknownFailure;

  /// Stable backend message key, when the backend sent one.
  final String? key;

  /// Short type name for logs and tests (never shown to users).
  String get type;

  @override
  bool operator ==(Object other) =>
      other is AppFailure &&
      other.runtimeType == runtimeType &&
      other.key == key;

  @override
  int get hashCode => Object.hash(runtimeType, key);

  @override
  String toString() =>
      key == null ? 'AppFailure.$type' : 'AppFailure.$type($key)';
}

/// The server could not be reached or answered with a transport error.
final class NetworkFailure extends AppFailure {
  const NetworkFailure({super.key});
  @override
  String get type => 'network';
}

/// The device has no usable network connection.
final class OfflineFailure extends AppFailure {
  const OfflineFailure();
  @override
  String get type => 'offline';
}

/// The request took too long.
final class TimeoutFailure extends AppFailure {
  const TimeoutFailure();
  @override
  String get type => 'timeout';
}

/// The caller is not allowed to do this (RLS, role checks, 0-row writes).
final class PermissionDeniedFailure extends AppFailure {
  const PermissionDeniedFailure({super.key});
  @override
  String get type => 'permissionDenied';
}

/// The row or resource does not exist (or is not visible to the caller).
final class NotFoundFailure extends AppFailure {
  const NotFoundFailure({super.key});
  @override
  String get type => 'notFound';
}

/// The input was rejected. [field] names the form field when known.
final class ValidationFailure extends AppFailure {
  const ValidationFailure({this.field, super.key});

  final String? field;

  @override
  String get type => 'validation';

  @override
  bool operator ==(Object other) =>
      other is ValidationFailure && other.field == field && other.key == key;

  @override
  int get hashCode => Object.hash(type, field, key);
}

/// The write conflicts with existing data (unique violation).
final class ConflictFailure extends AppFailure {
  const ConflictFailure({super.key});
  @override
  String get type => 'conflict';
}

/// Too many requests; [retryAfter] is set when the server says when.
final class RateLimitedFailure extends AppFailure {
  const RateLimitedFailure({this.retryAfter}) : super(key: 'rate_limited');

  final DateTime? retryAfter;

  @override
  String get type => 'rateLimited';
}

/// A daily or plan quota is used up.
final class QuotaExceededFailure extends AppFailure {
  const QuotaExceededFailure() : super(key: 'quota_exceeded');
  @override
  String get type => 'quotaExceeded';
}

/// The session is missing, expired or revoked; the user must sign in again.
final class SessionExpiredFailure extends AppFailure {
  const SessionExpiredFailure();
  @override
  String get type => 'sessionExpired';
}

/// The account's email address is not confirmed yet.
final class EmailNotConfirmedFailure extends AppFailure {
  const EmailNotConfirmedFailure() : super(key: 'email_not_confirmed');
  @override
  String get type => 'emailNotConfirmed';
}

/// Wrong email or password.
final class InvalidCredentialsFailure extends AppFailure {
  const InvalidCredentialsFailure();
  @override
  String get type => 'invalidCredentials';
}

/// An account with this email already exists.
final class AccountExistsFailure extends AppFailure {
  const AccountExistsFailure();
  @override
  String get type => 'accountExists';
}

/// The password does not meet the server's policy.
final class WeakPasswordFailure extends AppFailure {
  const WeakPasswordFailure({this.reasons = const []});

  final List<String> reasons;

  @override
  String get type => 'weakPassword';
}

/// A one-time code or link has expired or is invalid.
final class CodeExpiredFailure extends AppFailure {
  const CodeExpiredFailure();
  @override
  String get type => 'codeExpired';
}

/// A business rule rejected the action; [key] says which one.
final class BusinessFailure extends AppFailure {
  const BusinessFailure(String key) : super(key: key);

  @override
  String get key => super.key!;

  @override
  String get type => 'business';
}

/// Anything not recognised. Logged with its stack, never shown raw.
final class UnknownFailure extends AppFailure {
  const UnknownFailure();
  @override
  String get type => 'unknown';
}

/// Maps backend, transport and platform errors to [AppFailure].
abstract final class ErrorMapper {
  static final RegExp _messageKey = RegExp(r'^[a-z][a-z0-9_]{1,63}$');

  /// Returns the [AppFailure] for [error]. Errors that are not recognised
  /// are logged (with [stackTrace]) and become [UnknownFailure].
  static AppFailure map(Object error, [StackTrace? stackTrace]) {
    final failure = _map(error);
    if (failure is UnknownFailure) {
      AppLogger.error(
        'Unexpected error (${error.runtimeType})',
        error,
        stackTrace ?? StackTrace.current,
      );
    }
    return failure;
  }

  /// Runs [action] and rethrows any error as an [AppFailure].
  static Future<T> guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(map(error, stackTrace), stackTrace);
    }
  }

  static AppFailure _map(Object error) {
    return switch (error) {
      AppFailure() => error,
      PostgrestException() => _postgrest(error),
      FunctionException() => _function(error),
      AuthException() => _auth(error),
      TimeoutException() => const AppFailure.timeout(),
      SocketException() => _socket(error),
      HandshakeException() => const AppFailure.network(),
      TlsException() => const AppFailure.network(),
      http.ClientException() => _clientException(error),
      HttpException() => const AppFailure.network(),
      _ => const AppFailure.unknown(),
    };
  }

  static String? _keyOf(String? message) {
    if (message == null) return null;
    final trimmed = message.trim();
    return _messageKey.hasMatch(trimmed) ? trimmed : null;
  }

  static AppFailure _postgrest(PostgrestException e) {
    final key = _keyOf(e.message);
    switch (e.code) {
      case '42501':
        return switch (key) {
          'not_authenticated' => const AppFailure.sessionExpired(),
          'email_not_confirmed' => const AppFailure.emailNotConfirmed(),
          'banned' || 'invite_email_mismatch' => AppFailure.business(key!),
          _ => AppFailure.permissionDenied(key: key),
        };
      case 'PGRST116':
        return const AppFailure.notFound();
      case 'PGRST301' || 'PGRST302' || 'PGRST303':
        return const AppFailure.sessionExpired();
      case '23505':
        return AppFailure.conflict(key: key);
      case '23514' || '23502' || '22P02' || '22001' || '22003' || '22007':
        return AppFailure.validation(key: key);
      case '22023':
        return AppFailure.validation(key: key);
      case 'P0001':
        return switch (key) {
          'rate_limited' => const AppFailure.rateLimited(),
          'quota_exceeded' => const AppFailure.quotaExceeded(),
          null => const AppFailure.unknown(),
          _ => AppFailure.business(key),
        };
      case 'P0002':
        return AppFailure.notFound(key: key);
      case '57014':
        return const AppFailure.timeout();
      case '401':
        return const AppFailure.sessionExpired();
      case '403':
        return AppFailure.permissionDenied(key: key);
      case '404':
        return AppFailure.notFound(key: key);
      case '408':
        return const AppFailure.timeout();
      case '429':
        return const AppFailure.rateLimited();
      case '500' || '502' || '503' || '504' || '520':
        return const AppFailure.network();
      default:
        return const AppFailure.unknown();
    }
  }

  static AppFailure _auth(AuthException e) {
    if (e is AuthSessionMissingException) {
      return const AppFailure.sessionExpired();
    }
    if (e is AuthWeakPasswordException) {
      return AppFailure.weakPassword(reasons: e.reasons);
    }
    if (e is AuthRetryableFetchException) {
      return _isOfflineMessage(e.message)
          ? const AppFailure.offline()
          : const AppFailure.network();
    }
    switch (e.code) {
      case 'invalid_credentials':
        return const AppFailure.invalidCredentials();
      case 'email_not_confirmed':
        return const AppFailure.emailNotConfirmed();
      case 'user_already_exists' || 'email_exists':
        return const AppFailure.accountExists();
      case 'weak_password':
        return const AppFailure.weakPassword();
      case 'over_email_send_rate_limit' ||
          'over_request_rate_limit' ||
          'over_sms_send_rate_limit':
        return const AppFailure.rateLimited();
      case 'otp_expired':
        return const AppFailure.codeExpired();
      case 'same_password':
        return const AppFailure.validation(
          field: 'password',
          key: 'same_password',
        );
      case 'email_address_invalid' || 'validation_failed':
        return const AppFailure.validation(
          field: 'email',
          key: 'invalid_email',
        );
      case 'session_expired' ||
          'session_not_found' ||
          'refresh_token_not_found' ||
          'refresh_token_already_used' ||
          'bad_jwt' ||
          'no_authorization':
        return const AppFailure.sessionExpired();
      case 'user_banned':
        return const AppFailure.business('banned');
      case 'signup_disabled' || 'email_provider_disabled':
        return const AppFailure.business('signup_disabled');
      case 'reauthentication_needed':
        return const AppFailure.business('reauth_required');
    }
    return switch (e.statusCode) {
      '401' => const AppFailure.sessionExpired(),
      '429' => const AppFailure.rateLimited(),
      '500' || '502' || '503' || '504' => const AppFailure.network(),
      _ => const AppFailure.unknown(),
    };
  }

  static AppFailure _function(FunctionException e) {
    if (e.status == 0) {
      final cause = e.details;
      if (cause is Object && cause is! String && cause is! Map) {
        final mapped = _map(cause);
        if (mapped is! UnknownFailure) return mapped;
      }
      return const AppFailure.network();
    }
    final body = e.details;
    String? code;
    String? reason;
    if (body is Map) {
      final err = body['error'];
      if (err is Map) {
        final c = err['code'];
        final r = err['reason'];
        if (c is String) code = c;
        if (r is String) reason = _keyOf(r);
      } else if (err is String) {
        code = err;
      }
    }
    switch (code) {
      case 'unauthorized':
        return const AppFailure.sessionExpired();
      case 'forbidden':
        return AppFailure.permissionDenied(key: reason);
      case 'not_found':
        return AppFailure.notFound(key: reason);
      case 'conflict':
        return AppFailure.conflict(key: reason ?? 'already_member');
      case 'too_long':
        return const AppFailure.validation(key: 'too_long');
      case 'invalid_request':
        return AppFailure.validation(key: reason);
      case 'rate_limited':
        return const AppFailure.rateLimited();
      case 'quota_exceeded':
        return const AppFailure.quotaExceeded();
      case 'consent_required' ||
          'reauth_required' ||
          'deletion_failed' ||
          'unavailable':
        return AppFailure.business(code!);
    }
    return switch (e.status) {
      401 => const AppFailure.sessionExpired(),
      403 => AppFailure.permissionDenied(key: reason),
      404 => AppFailure.notFound(key: reason),
      408 => const AppFailure.timeout(),
      409 => AppFailure.conflict(key: reason),
      400 || 413 || 422 => AppFailure.validation(key: reason),
      429 => const AppFailure.rateLimited(),
      >= 500 => const AppFailure.business('unavailable'),
      _ => const AppFailure.unknown(),
    };
  }

  static AppFailure _socket(SocketException e) {
    return _isOfflineMessage('${e.message} ${e.osError?.message ?? ''}') ||
            const {7, 101, 113}.contains(e.osError?.errorCode)
        ? const AppFailure.offline()
        : const AppFailure.network();
  }

  static AppFailure _clientException(http.ClientException e) {
    return _isOfflineMessage(e.message)
        ? const AppFailure.offline()
        : const AppFailure.network();
  }

  static bool _isOfflineMessage(String message) {
    final lower = message.toLowerCase();
    return lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('no address associated') ||
        lower.contains('no route to host');
  }
}
