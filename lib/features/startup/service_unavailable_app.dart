import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';

/// Shown instead of the app when the build configuration is invalid or the
/// backend client cannot start. It never falls back to demo data.
class ServiceUnavailableApp extends StatelessWidget {
  const ServiceUnavailableApp({
    super.key,
    this.problems = const [],
    this.showDetails = !kReleaseMode,
    this.themeMode = ThemeMode.system,
  });

  /// Configuration problems, shown only when [showDetails] is true.
  final List<String> problems;

  /// Whether to list technical details. Always false in release builds.
  final bool showDetails;

  final ThemeMode themeMode;

  static const String title = 'Service unavailable';
  static const String message =
      "Exevra can't connect right now. "
      'Please update the app or try again later.';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: _ServiceUnavailableScreen(
        problems: showDetails && !kReleaseMode ? problems : const [],
      ),
    );
  }
}

class _ServiceUnavailableScreen extends StatelessWidget {
  const _ServiceUnavailableScreen({required this.problems});

  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 56,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    ServiceUnavailableApp.title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    ServiceUnavailableApp.message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  if (problems.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Debug details',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colors.onErrorContainer,
                            ),
                          ),
                          const SizedBox(height: 6),
                          for (final problem in problems)
                            Text(
                              '• $problem',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onErrorContainer,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
