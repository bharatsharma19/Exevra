import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n.dart';
import '../logging/app_logger.dart';
import '../widgets/app_snackbar.dart';
import 'app_config.dart';

/// Opens [uri] outside the app and reports whether it opened.
typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);

/// Opens [uri] in the browser or the app registered for its scheme (for
/// example the email app for `mailto:`).
Future<bool> launchExternalUrl(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Public web pages and contact details of the app, all derived from
/// [AppConfig.appLinkHost], so a build for another domain needs no code
/// change.
///
/// * [privacyPolicy]: `https://<host>/privacy`
/// * [terms]: `https://<host>/terms`
/// * [deleteAccount]: `https://<host>/delete-account` (the store-required
///   page that explains account deletion without the app)
/// * [support]: `https://<host>/support`
/// * [supportEmail]: `support@<host>`
@immutable
class LegalLinks {
  /// Creates the links for [host], a plain host name such as `exevra.app`.
  const LegalLinks(this.host);

  /// The links for [config]'s app link host.
  factory LegalLinks.fromConfig(AppConfig config) =>
      LegalLinks(config.appLinkHost.trim());

  /// The links of the configuration compiled into this build.
  static final LegalLinks current = LegalLinks.fromConfig(
    AppConfig.environment,
  );

  /// Host every link is built on.
  final String host;

  /// Privacy policy page.
  Uri get privacyPolicy => _page('privacy');

  /// Terms of use page.
  Uri get terms => _page('terms');

  /// Account deletion page (how to delete an account and its data).
  Uri get deleteAccount => _page('delete-account');

  /// Help and support page.
  Uri get support => _page('support');

  /// Support email address.
  String get supportEmail => 'support@$host';

  /// A `mailto:` link to [supportEmail] with an optional [subject] and
  /// [body].
  ///
  /// The query is percent-encoded by hand: [Uri.queryParameters] would encode
  /// spaces as `+`, which many email apps show literally.
  Uri supportEmailUri({String? subject, String? body}) {
    final fields = <String, String>{'subject': ?subject, 'body': ?body};
    return Uri(
      scheme: 'mailto',
      path: supportEmail,
      query: fields.isEmpty
          ? null
          : fields.entries
                .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
                .join('&'),
    );
  }

  Uri _page(String path) => Uri(scheme: 'https', host: host, path: '/$path');

  @override
  bool operator ==(Object other) => other is LegalLinks && other.host == host;

  @override
  int get hashCode => host.hashCode;

  @override
  String toString() => 'LegalLinks($host)';
}

/// Opens [uri] outside the app with [launcher] (the platform launcher by
/// default).
///
/// When nothing can open it (no browser or email app, or the platform call
/// fails), shows an error snackbar with [failureMessage] or a generic
/// "Couldn't open the link" message, and returns false.
Future<bool> openExternal(
  BuildContext context,
  Uri uri, {
  String? failureMessage,
  ExternalUrlLauncher? launcher,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final message = failureMessage ?? context.l10n.linkOpenFailed;
  var opened = false;
  try {
    opened = await (launcher ?? launchExternalUrl)(uri);
  } on Object catch (error) {
    // The URI is not logged: a mailto link can carry the app version and
    // later the user's own text.
    AppLogger.warn('Could not open an external ${uri.scheme} link', error);
  }
  if (!opened) {
    AppSnackbar.showError(
      message,
      messenger: messenger != null && messenger.mounted ? messenger : null,
    );
  }
  return opened;
}
