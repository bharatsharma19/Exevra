import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

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
///
/// Because the outer scaffold cannot see the pages' bottom chrome or resize
/// for the keyboard (the navigator must keep its full height), it lifts
/// floating snackbars itself: above the soft keyboard, and above any
/// [SnackbarClearance] (the page's [NavigationBar] or FAB) on the current
/// route.
class SnackbarHost extends StatefulWidget {
  /// Creates the host.
  const SnackbarHost({required this.child, super.key});

  /// The navigator (router output).
  final Widget child;

  @override
  State<SnackbarHost> createState() => _SnackbarHostState();
}

class _SnackbarHostState extends State<SnackbarHost> {
  final Map<Object, double> _clearances = {};
  bool _updateScheduled = false;
  (ThemeData, double)? _cacheKey;
  ThemeData? _cachedTheme;

  double get _clearance => _clearances.values.fold(0, math.max);

  RenderBox? get _box {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? box : null;
  }

  void _report(Object owner, double? clearance) {
    final old = _clearances[owner];
    if (clearance == null) {
      if (_clearances.remove(owner) == null) return;
    } else {
      if (old != null && (old - clearance).abs() < 0.5) return;
      _clearances[owner] = clearance;
    }
    if (_updateScheduled) return;
    _updateScheduled = true;
    // Reports arrive during paint or unmount; rebuild on the next frame.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      if (mounted) setState(() {});
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  ThemeData _hostTheme(ThemeData theme, double lift) {
    final key = (theme, lift);
    if (_cacheKey == key && _cachedTheme != null) return _cachedTheme!;
    final base =
        theme.snackBarTheme.insetPadding ??
        const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        );
    _cacheKey = key;
    return _cachedTheme = theme.copyWith(
      snackBarTheme: theme.snackBarTheme.copyWith(
        insetPadding: base.copyWith(bottom: base.bottom + lift),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final lift = math.max(keyboard, _clearance);
    // The lifted snackbar theme applies to this scaffold (and so to its
    // snackbar slot) only; the navigator keeps the app theme unchanged, so
    // pages do not rebuild while the keyboard animates.
    return Theme(
      data: _hostTheme(theme, lift),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Theme(
          data: theme,
          child: _SnackbarHostScope(host: this, child: widget.child),
        ),
      ),
    );
  }
}

class _SnackbarHostScope extends InheritedWidget {
  const _SnackbarHostScope({required this.host, required super.child});

  final _SnackbarHostState host;

  static _SnackbarHostState? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_SnackbarHostScope>()?.host;

  @override
  bool updateShouldNotify(_SnackbarHostScope oldWidget) =>
      host != oldWidget.host;
}

/// Marks bottom chrome (a page's [NavigationBar], bottom app bar or FAB)
/// that [AppSnackbar] messages must not cover.
///
/// While its route is the current one, the [SnackbarHost] lifts floating
/// snackbars above the top edge of this widget. Without a host it does
/// nothing.
///
/// ```dart
/// Scaffold(
///   bottomNavigationBar: SnackbarClearance(child: NavigationBar(...)),
/// )
/// ```
class SnackbarClearance extends StatefulWidget {
  /// Creates a clearance marker around [child].
  const SnackbarClearance({required this.child, super.key});

  /// The bottom chrome.
  final Widget child;

  @override
  State<SnackbarClearance> createState() => _SnackbarClearanceState();
}

class _SnackbarClearanceState extends State<SnackbarClearance> {
  _SnackbarHostState? _host;
  bool _active = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = _SnackbarHostScope.maybeOf(context);
    if (host != _host) _host?._report(this, null);
    _host = host;
    // Depends on the route, so this rebuilds when another route covers it.
    _active = ModalRoute.isCurrentOf(context) ?? true;
    if (!_active) _host?._report(this, null);
  }

  @override
  void dispose() {
    _host?._report(this, null);
    super.dispose();
  }

  void _measure(RenderBox box) {
    final host = _host;
    if (host == null || !_active || !box.attached) return;
    final hostBox = host._box;
    if (hostBox == null) return;
    final top = box.localToGlobal(Offset.zero, ancestor: hostBox).dy;
    host._report(this, math.max(0, hostBox.size.height - top));
  }

  @override
  Widget build(BuildContext context) =>
      _MeasureOnPaint(onPaint: _measure, child: widget.child);
}

class _MeasureOnPaint extends SingleChildRenderObjectWidget {
  const _MeasureOnPaint({required this.onPaint, super.child});

  final ValueChanged<RenderBox> onPaint;

  @override
  _RenderMeasureOnPaint createRenderObject(BuildContext context) =>
      _RenderMeasureOnPaint(onPaint);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureOnPaint renderObject,
  ) => renderObject.onPaint = onPaint;
}

class _RenderMeasureOnPaint extends RenderProxyBox {
  _RenderMeasureOnPaint(this.onPaint);

  ValueChanged<RenderBox> onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onPaint(this);
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
      // The theme's action colour is meant for the inverse surface; on the
      // tinted containers only the kind's foreground reaches 4.5:1.
      action: action == null
          ? null
          : SnackBarAction(
              key: action.key,
              label: action.label,
              onPressed: action.onPressed,
              textColor: style.foreground,
              disabledTextColor: style.foreground,
              backgroundColor: action.backgroundColor,
              disabledBackgroundColor: action.disabledBackgroundColor,
            ),
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
