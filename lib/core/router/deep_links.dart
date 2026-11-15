import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../logging/app_logger.dart';

/// A link the app knows how to open.
sealed class DeepLink {
  const DeepLink();
}

/// A group invitation (`https://<host>/invite/<token>`,
/// `exevra://invite/<token>`, or the older `?token=` forms).
final class InviteLink extends DeepLink {
  const InviteLink(this.token);

  final String token;

  @override
  bool operator ==(Object other) => other is InviteLink && other.token == token;

  @override
  int get hashCode => token.hashCode;

  @override
  String toString() => 'InviteLink(<token>)';
}

/// An auth email link (`com.exevra.app://auth-callback`). supabase_flutter
/// exchanges it for a session; the app only ignores it.
final class AuthCallbackLink extends DeepLink {
  const AuthCallbackLink();
}

abstract final class DeepLinks {
  /// Invitation tokens are base64url (43 characters today).
  static final RegExp _token = RegExp(r'^[A-Za-z0-9_-]{16,128}$');

  static bool isValidToken(String? token) =>
      token != null && _token.hasMatch(token);

  /// Parses [uri]; returns null for anything the app does not handle.
  static DeepLink? parse(Uri uri, {required String appLinkHost}) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();

    if ('${uri.scheme}://${uri.host}'.toLowerCase() ==
        AppConfig.authCallbackUrl) {
      return const AuthCallbackLink();
    }

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final List<String> inviteSegments;
    if (scheme == 'https' &&
        (host == appLinkHost.toLowerCase() ||
            host == 'www.${appLinkHost.toLowerCase()}')) {
      // https://<host>/invite/<token> or /invite?token=<token>
      if (segments.isEmpty || segments.first != 'invite') return null;
      inviteSegments = segments.sublist(1);
    } else if (scheme == AppConfig.inviteScheme && host == 'invite') {
      // exevra://invite/<token> or exevra://invite?token=<token>
      inviteSegments = segments;
    } else {
      return null;
    }
    final token = switch (inviteSegments) {
      [final token] => token,
      [] => uri.queryParameters['token'],
      _ => null,
    };
    return isValidToken(token) ? InviteLink(token!) : null;
  }

  /// Parameters that carry a session. A callback with any of them is an
  /// implicit-flow link, which this app never asks for: accepting one
  /// would let any web page sign the device into another account.
  static const Set<String> _sessionParameters = {
    'access_token',
    'refresh_token',
    'provider_token',
    'provider_refresh_token',
  };

  /// Whether supabase_flutter may exchange [uri] for a session: only the
  /// PKCE auth callback, which carries a one-time `code` (or an error)
  /// that works only with the verifier this device stored when it started
  /// the flow.
  ///
  /// The query and the fragment are read together, the way gotrue reads
  /// them, so tokens hidden in either reject the link.
  static bool isSessionCallback(Uri uri, {required String appLinkHost}) {
    if (parse(uri, appLinkHost: appLinkHost) is! AuthCallbackLink) {
      return false;
    }
    final Map<String, String> parameters;
    try {
      final text = uri.toString();
      parameters = Uri.parse(
        uri.hasQuery ? text.replaceAll('#', '&') : text.replaceAll('#', '?'),
      ).queryParameters;
    } on FormatException {
      return false;
    }
    if (parameters.keys.any(_sessionParameters.contains)) return false;
    return parameters.containsKey('code') ||
        parameters.containsKey('error') ||
        parameters.containsKey('error_code') ||
        parameters.containsKey('error_description');
  }
}

/// Where incoming links come from (app_links; a fake in tests).
abstract interface class LinkSource {
  Future<Uri?> initialLink();
  Stream<Uri> get links;
}

class AppLinksSource implements LinkSource {
  AppLinksSource([AppLinks? appLinks]) : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;

  @override
  Future<Uri?> initialLink() => _appLinks.getInitialLink();

  @override
  Stream<Uri> get links => _appLinks.uriLinkStream;
}

final linkSourceProvider = Provider<LinkSource>((ref) => AppLinksSource());

/// Listens for incoming links for as long as it is watched and passes each
/// recognised one to [onLink]. The platform may report one tap twice (the
/// initial link and the first stream event), so a link equal to the
/// previous one within [duplicateWindow] is ignored; opening the same link
/// again later works.
class DeepLinkListener {
  DeepLinkListener({
    required LinkSource source,
    required this.onLink,
    String? appLinkHost,
    DateTime Function()? clock,
  }) : _host = appLinkHost ?? AppConfig.environment.appLinkHost,
       _clock = clock ?? DateTime.now {
    unawaited(source.initialLink().then(_handle, onError: _onError));
    _sub = source.links.listen(_handle, onError: _onError);
  }

  static const Duration duplicateWindow = Duration(seconds: 2);

  final void Function(DeepLink link) onLink;
  final String _host;
  final DateTime Function() _clock;
  late final StreamSubscription<Uri> _sub;
  Uri? _last;
  DateTime? _lastAt;

  void _handle(Uri? uri) {
    if (uri == null) return;
    final now = _clock();
    final lastAt = _lastAt;
    if (uri == _last &&
        lastAt != null &&
        now.difference(lastAt) < duplicateWindow) {
      return;
    }
    _last = uri;
    _lastAt = now;
    final link = DeepLinks.parse(uri, appLinkHost: _host);
    if (link == null) {
      AppLogger.info('Ignored a link the app does not handle');
      return;
    }
    onLink(link);
  }

  void _onError(Object error) {
    // MissingPluginException in tests, or a malformed link.
    if (kDebugMode) AppLogger.info('Link listener: ${error.runtimeType}');
  }

  Future<void> dispose() => _sub.cancel();
}
