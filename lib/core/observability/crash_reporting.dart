import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/app_config.dart';
import '../logging/app_logger.dart';
import 'pii_scrubber.dart';

/// Whether this build reports crashes to Sentry (a SENTRY_DSN was compiled in).
bool get isCrashReportingConfigured =>
    AppConfig.environment.sentryDsn.trim().isNotEmpty;

/// Runs [appRunner] with crash reporting installed.
///
/// Without a `SENTRY_DSN` define, uncaught Flutter and platform errors are
/// only logged through [AppLogger] (which is silent in release builds). With
/// one, Sentry is initialised first, with personal data scrubbed by
/// [PiiScrubber]. Use it as the body of `main`:
///
/// ```dart
/// Future<void> main() => runAppGuarded(_bootstrap);
/// ```
Future<void> runAppGuarded(FutureOr<void> Function() appRunner) async {
  final dsn = AppConfig.environment.sentryDsn.trim();
  if (dsn.isEmpty) {
    installLocalErrorHandlers();
    await appRunner();
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();
  try {
    final release = await _releaseName();
    await SentryFlutter.init(
      (options) => configureSentry(options, dsn, release),
    );
  } catch (error, stackTrace) {
    // A malformed DSN or a native SDK failure must never stop the app.
    AppLogger.error('Crash reporting could not start', error, stackTrace);
    installLocalErrorHandlers();
  }
  await appRunner();
}

/// Applies Exevra's Sentry settings to [options].
@visibleForTesting
void configureSentry(
  SentryFlutterOptions options,
  String dsn,
  String? release,
) {
  options
    ..dsn = dsn
    ..environment = AppConfig.appEnvironment
    ..sendDefaultPii = false
    ..tracesSampleRate = 0.05
    ..attachScreenshot = false
    ..attachViewHierarchy = false
    ..beforeSend = PiiScrubber.scrubEvent
    ..beforeBreadcrumb = PiiScrubber.scrubBreadcrumb;
  if (release != null) options.release = release;
}

/// Installs handlers that log uncaught errors instead of reporting them.
@visibleForTesting
void installLocalErrorHandlers() {
  FlutterError.onError = (details) {
    AppLogger.error('Uncaught Flutter error', details.exception, details.stack);
    if (kDebugMode) FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppLogger.error('Uncaught platform error', error, stackTrace);
    return true;
  };
}

/// Records a handled failure: logs it and, when crash reporting is enabled,
/// sends it to Sentry (scrubbed like every other event).
Future<void> captureFailure(Object error, StackTrace stackTrace) async {
  AppLogger.error('Handled failure', error, stackTrace);
  if (!Sentry.isEnabled) return;
  try {
    await Sentry.captureException(error, stackTrace: stackTrace);
  } catch (sendError) {
    AppLogger.warn('Could not report a failure', sendError);
  }
}

/// `<package>@<version>+<build>`, Sentry's release naming.
Future<String?> _releaseName() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.packageName}@${info.version}+${info.buildNumber}';
  } catch (error) {
    AppLogger.warn('Could not read the app version for crash reports', error);
    return null;
  }
}
