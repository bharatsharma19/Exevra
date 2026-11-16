import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import 'snackbar_host.dart';

export 'snackbar_host.dart';

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

  /// Shows [message] with an Undo action; see [showUndoSnackbar].
  static Future<bool> showUndo(
    String message, {
    String? undoLabel,
    Duration duration = AppDurations.undoSnackbar,
    ScaffoldMessengerState? messenger,
  }) => showUndoSnackbar(
    message,
    undoLabel: undoLabel,
    duration: duration,
    messenger: messenger,
  );

  /// Shows an error message. [message] must be user-friendly.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showError(
    String message, {
    ScaffoldMessengerState? messenger,
  }) => show(message, kind: AppSnackbarKind.error, messenger: messenger);

  /// Shows [message] with the colours of [kind]. An [action] is redrawn in
  /// the kind's foreground colour so it stays readable on the tinted fill.
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
      // The theme's action colours are meant for the inverse surface; on the
      // tinted containers only the kind's foreground reaches 4.5:1. A focused
      // action inverts within the kind's pair (foreground fill, container
      // label), so the focus indicator is at least 4.5:1 against the
      // snackbar instead of the theme's near-invisible onInverseSurface fill.
      action: action == null
          ? null
          : SnackBarAction(
              key: action.key,
              label: action.label,
              onPressed: action.onPressed,
              textColor: WidgetStateColor.resolveWith(
                (states) => _actionFocused(states)
                    ? style.background
                    : style.foreground,
              ),
              disabledTextColor: style.foreground,
              backgroundColor: WidgetStateColor.resolveWith(
                (states) => _actionFocused(states)
                    ? style.foreground
                    : Colors.transparent,
              ),
            ),
      persist: persist ?? MediaQuery.accessibleNavigationOf(context),
      // The fill is fixed now, so the text keeps the matching colour even
      // if the theme changes while the message shows.
      content: AppSnackbarContent(
        message,
        kind: kind,
        foreground: style.foreground,
      ),
    );
  }
}

bool _actionFocused(Set<WidgetState> states) =>
    states.contains(WidgetState.focused) &&
    !states.contains(WidgetState.disabled);

/// The icon and message row of an [AppSnackbar], with its screen reader
/// label ("Error. Could not save").
class AppSnackbarContent extends StatelessWidget {
  /// Creates the content for [kind].
  const AppSnackbarContent(
    this.message, {
    this.kind = AppSnackbarKind.info,
    this.foreground,
    super.key,
  });

  /// The message.
  final String message;

  /// Tone of the message.
  final AppSnackbarKind kind;

  /// Icon and text colour; defaults to the kind's foreground in the
  /// current theme. A shown snack bar passes the colour that matches the
  /// fill it was shown with.
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final style = _SnackStyle.of(context, kind);
    final color = foreground ?? style.foreground;
    final textStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: color);
    return Semantics(
      label: '${style.label}. $message',
      excludeSemantics: true,
      child: Row(
        children: [
          Icon(style.icon, color: color, size: AppSizes.icon),
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
  final controller = AppSnackbar.show(
    message,
    duration: duration,
    messenger: target,
    action: SnackBarAction(
      label: undoLabel ?? target.context.l10n.undo,
      onPressed: () {},
    ),
  );
  if (controller == null) return false;
  final reason = await controller.closed;
  return reason == SnackBarClosedReason.action;
}
