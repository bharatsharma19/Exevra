import 'package:flutter/material.dart';

import '../../../core/widgets/app_snackbar.dart';

/// Shows [message] as an [AppSnackbar] of [kind].
///
/// Uses the app-wide messenger (so the message paints above sheets and
/// dialogs) and falls back to the nearest [ScaffoldMessenger] when the app
/// root is not mounted, for example in isolated widget tests.
void showFeatureSnackbar(
  BuildContext context,
  String message, {
  AppSnackbarKind kind = AppSnackbarKind.info,
}) {
  final messenger =
      rootScaffoldMessengerKey.currentState ??
      ScaffoldMessenger.maybeOf(context);
  AppSnackbar.show(message, kind: kind, messenger: messenger);
}
