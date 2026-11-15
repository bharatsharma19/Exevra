import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// The app-wide [ScaffoldMessenger] key. Pass it to
/// `MaterialApp.scaffoldMessengerKey` and wrap the router output in
/// [SnackbarHost] so [AppSnackbar] messages render above modal sheets and
/// dialogs.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>(debugLabel: 'rootScaffoldMessenger');

/// Hosts snackbars above every route, including modal bottom sheets.
///
/// Use it in `MaterialApp.builder`:
///
/// ```dart
/// builder: (context, child) => SnackbarHost(child: child!),
/// ```
///
/// It is a transparent [Scaffold] around the navigator. Page scaffolds below
/// it become nested scaffolds, so the [ScaffoldMessenger] shows snackbars on
/// this outer one, which paints over any modal route.
class SnackbarHost extends StatelessWidget {
  /// Creates the host.
  const SnackbarHost({required this.child, super.key});

  /// The navigator (router output).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: child,
    );
  }
}

/// Tone of an [AppSnackbar] message.
enum AppSnackbarKind {
  /// Something completed ("Expense saved").
  success,

  /// Neutral information.
  info,

  /// Something failed. Pass a friendly message, never a raw exception.
  error,
}

/// Theme-aware snackbars shown through [rootScaffoldMessengerKey].
///
/// Each kind uses its container colour pair (at least 4.5:1) plus an icon, and
/// screen readers hear the kind before the message ("Error. Could not save"),
/// so the tone never depends on colour alone. Showing a message replaces the
/// current one instead of queueing behind it.
abstract final class AppSnackbar {
  /// Shows a success message.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showSuccess(
    String message, {
    ScaffoldMessengerState? messenger,
  }) => show(message, kind: AppSnackbarKind.success, messenger: messenger);

  /// Shows an informational message.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showInfo(
    String message, {
    ScaffoldMessengerState? messenger,
  }) => show(message, messenger: messenger);

  /// Shows an error message. [message] must be user-friendly.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showError(
    String message, {
    ScaffoldMessengerState? messenger,
  }) => show(message, kind: AppSnackbarKind.error, messenger: messenger);

  /// Shows [message] with the colours of [kind].
  ///
  /// Uses [messenger] or, by default, [rootScaffoldMessengerKey]. Returns
  /// null when no messenger is mounted.
  ///
  /// The message closes after [duration] unless [persist] is true. By default
  /// it persists only while a screen reader drives navigation, so TalkBack
  /// and VoiceOver users have time to reach the action.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? show(
    String message, {
    AppSnackbarKind kind = AppSnackbarKind.info,
    Duration duration = AppDurations.snackbar,
    SnackBarAction? action,
    bool? persist,
    ScaffoldMessengerState? messenger,
  }) {
    final target = messenger ?? rootScaffoldMessengerKey.currentState;
    if (target == null || !target.mounted) return null;
    final snackBar = build(
      target.context,
      message,
      kind: kind,
      duration: duration,
      action: action,
      persist: persist,
    );
    target.hideCurrentSnackBar();
    return target.showSnackBar(snackBar);
  }

  /// Builds the [SnackBar] for [kind] using the theme at [context]. Exposed
  /// for previews and tests; prefer [show].
  static SnackBar build(
    BuildContext context,
    String message, {
    AppSnackbarKind kind = AppSnackbarKind.info,
    Duration duration = AppDurations.snackbar,
    SnackBarAction? action,
    bool? persist,
  }) {
    final style = _SnackStyle.of(context, kind);
    return SnackBar(
      duration: duration,
      backgroundColor: style.background,
      behavior: SnackBarBehavior.floating,
      shape: style.shape,
      action: action,
      persist: persist ?? MediaQuery.accessibleNavigationOf(context),
      content: AppSnackbarContent(message, kind: kind),
    );
  }
}

/// The icon and message row of an [AppSnackbar], with its screen reader
/// label ("Error. Could not save").
class AppSnackbarContent extends StatelessWidget {
  /// Creates the content for [kind].
  const AppSnackbarContent(
    this.message, {
    this.kind = AppSnackbarKind.info,
    super.key,
  });

  /// The message.
  final String message;

  /// Tone of the message.
  final AppSnackbarKind kind;

  @override
  Widget build(BuildContext context) {
    final style = _SnackStyle.of(context, kind);
    final textStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: style.foreground);
    return Semantics(
      label: '${style.label}. $message',
      excludeSemantics: true,
      child: Row(
        children: [
          Icon(style.icon, color: style.foreground, size: AppSizes.icon),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(message, style: textStyle)),
        ],
      ),
    );
  }
}

/// A static rendering of an [AppSnackbar] message (no animation, no
/// messenger), for galleries and golden tests.
class AppSnackbarPreview extends StatelessWidget {
  /// Creates a preview of [kind].
  const AppSnackbarPreview(
    this.message, {
    this.kind = AppSnackbarKind.info,
    super.key,
  });

  /// The message.
  final String message;

  /// Tone of the message.
  final AppSnackbarKind kind;

  @override
  Widget build(BuildContext context) {
    final style = _SnackStyle.of(context, kind);
    return Material(
      color: style.background,
      shape: style.shape,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 14,
        ),
        child: AppSnackbarContent(message, kind: kind),
      ),
    );
  }
}

/// Colours, icon and spoken label of one [AppSnackbarKind].
class _SnackStyle {
  const _SnackStyle(
    this.background,
    this.foreground,
    this.edge,
    this.icon,
    this.label,
  );

  factory _SnackStyle.of(BuildContext context, AppSnackbarKind kind) {
    final palette = context.palette;
    final l10n = context.l10n;
    return switch (kind) {
      AppSnackbarKind.success => _SnackStyle(
        palette.successContainer,
        palette.onSuccessContainer,
        palette.success,
        Icons.check_circle_outline,
        l10n.snackbarSuccessLabel,
      ),
      AppSnackbarKind.info => _SnackStyle(
        palette.infoContainer,
        palette.onInfoContainer,
        palette.info,
        Icons.info_outline,
        l10n.snackbarInfoLabel,
      ),
      AppSnackbarKind.error => _SnackStyle(
        palette.dangerContainer,
        palette.onDangerContainer,
        palette.danger,
        Icons.error_outline,
        l10n.snackbarErrorLabel,
      ),
    };
  }

  final Color background;
  final Color foreground;
  final Color edge;
  final IconData icon;
  final String label;

  ShapeBorder get shape => RoundedRectangleBorder(
    borderRadius: AppRadius.mdAll,
    side: BorderSide(color: edge),
  );
}

/// Shows [message] with an Undo action and resolves to `true` if the user
/// tapped Undo before the snackbar closed.
///
/// Typical use: remove the item from the UI, call this, and only commit the
/// deletion when it resolves to `false`. A newer snackbar replaces this one
/// and resolves it to `false`. Resolves to `false` immediately when no
/// messenger is mounted. With TalkBack or VoiceOver on, the snackbar stays
/// until dismissed, so the user has time to reach Undo.
Future<bool> showUndoSnackbar(
  String message, {
  String? undoLabel,
  Duration duration = AppDurations.undoSnackbar,
  ScaffoldMessengerState? messenger,
}) async {
  final target = messenger ?? rootScaffoldMessengerKey.currentState;
  if (target == null || !target.mounted) return false;
  final palette = target.context.palette;
  final controller = AppSnackbar.show(
    message,
    duration: duration,
    messenger: target,
    action: SnackBarAction(
      label: undoLabel ?? target.context.l10n.undo,
      textColor: palette.onInfoContainer,
      onPressed: () {},
    ),
  );
  if (controller == null) return false;
  final reason = await controller.closed;
  return reason == SnackBarClosedReason.action;
}
