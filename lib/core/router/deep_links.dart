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
/// recognised one to [onLink] once (the initial link may arrive twice).
class DeepLinkListener {
  DeepLinkListener({
    required LinkSource source,
    required this.onLink,
    String? appLinkHost,
  }) : _host = appLinkHost ?? AppConfig.environment.appLinkHost {
    unawaited(source.initialLink().then(_handle, onError: _onError));
    _sub = source.links.listen(_handle, onError: _onError);
  }

  final void Function(DeepLink link) onLink;
  final String _host;
  late final StreamSubscription<Uri> _sub;
  Uri? _last;

  void _handle(Uri? uri) {
    if (uri == null || uri == _last) return;
    _last = uri;
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
