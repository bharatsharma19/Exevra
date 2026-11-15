import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

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
