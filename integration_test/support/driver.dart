/// Helpers to drive the real app on a device: waiting in real time
/// (the app keeps animating, so pumpAndSettle is not used), tapping,
/// typing, screenshots in both themes, and a step log with timings.
library;

import 'dart:io';

import 'package:expense_manager/models/profile.dart';
import 'package:expense_manager/main.dart';
import 'package:expense_manager/providers/profile_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'e2e_env.dart';

/// Pumps frames for [duration] of real time.
Future<void> settle(
  WidgetTester tester, [
  Duration duration = const Duration(milliseconds: 600),
]) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Pumps until [finder] finds something, or fails after [timeout].
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out after $timeout waiting for ${reason ?? finder}');
}

/// Pumps until [condition] holds, or fails after [timeout].
Future<void> waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
  required String reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (condition()) return;
  }
  throw TestFailure('Timed out after $timeout waiting for $reason');
}

/// Pumps until [finder] finds nothing.
Future<void> waitForGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  String? reason,
}) => waitUntil(
  tester,
  () => finder.evaluate().isEmpty,
  timeout: timeout,
  reason: '${reason ?? finder} to go away',
);

/// Whether [finder] finds something within [timeout] (no failure).
Future<bool> appears(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return true;
  }
  return false;
}

/// Scrolls [finder] into view, taps it and lets the app react.
Future<void> tapOn(
  WidgetTester tester,
  Finder finder, {
  Duration after = const Duration(milliseconds: 600),
}) async {
  await waitFor(tester, finder);
  final target = finder.first;
  await tester.ensureVisible(target);
  await settle(tester, const Duration(milliseconds: 300));
  await tester.tap(target);
  await settle(tester, after);
}

/// Types [text] into the editable field at or below [finder].
Future<void> typeInto(WidgetTester tester, Finder finder, String text) async {
  await waitFor(tester, finder);
  final editable = find.descendant(
    of: finder.first,
    matching: find.byType(EditableText),
    matchRoot: true,
  );
  await tester.ensureVisible(editable.first);
  await settle(tester, const Duration(milliseconds: 200));
  await tester.tap(editable.first);
  await tester.pump();
  await tester.enterText(editable.first, text);
  await settle(tester, const Duration(milliseconds: 300));
}

/// Taps the bottom navigation destination labelled [label].
Future<void> goToTab(WidgetTester tester, String label) => tapOn(
  tester,
  find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  after: const Duration(milliseconds: 900),
);

/// Pulls [scrollable] down to refresh.
Future<void> pullToRefresh(WidgetTester tester, Finder scrollable) async {
  await tester.fling(scrollable.first, const Offset(0, 600), 1500);
  await settle(tester, const Duration(seconds: 2));
}

ProviderContainer appContainer(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ExevraApp)));

/// Whether the app currently draws its dark theme.
bool isDark(WidgetTester tester) {
  final context = tester.element(find.byType(Navigator).first);
  return Theme.of(context).brightness == Brightness.dark;
}

/// Screenshots by the host (integration_test/screenshot_server.py), named
/// `<nn>_<name>_<light|dark>.png`.
class Screens {
  Screens(this.tester);

  final WidgetTester tester;
  final List<String> taken = [];
  final List<String> failed = [];
  int _n = 0;
  bool? _available;

  Future<bool> _ping() async {
    if (E2eEnv.shotUrl.isEmpty) return false;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3);
      final req = await client.getUrl(Uri.parse('${E2eEnv.shotUrl}/ping'));
      final res = await req.close();
      await res.drain<void>();
      client.close();
      return res.statusCode == 200;
    } on Object {
      return false;
    }
  }

  Future<void> _capture(String file, {bool keyboard = false}) async {
    _available ??= await _ping();
    if (!_available!) return;
    // The soft keyboard covers most of a form; it stays only when asked.
    if (!keyboard) FocusManager.instance.primaryFocus?.unfocus();
    // Let animations and pointer markers finish first.
    await settle(tester, const Duration(milliseconds: 900));
    final client = HttpClient();
    try {
      final uri = Uri.parse(
        '${E2eEnv.shotUrl}/shot',
      ).replace(queryParameters: {'name': file});
      final res = await (await client.getUrl(uri)).close();
      await res.drain<void>();
      (res.statusCode == 200 ? taken : failed).add('$file.png');
    } on Object catch (e) {
      failed.add('$file.png ($e)');
    } finally {
      client.close();
    }
  }

  /// One screenshot in the current theme.
  Future<void> current(String name, {bool keyboard = false}) async {
    _n++;
    final number = _n.toString().padLeft(2, '0');
    await _capture(
      '${number}_${name}_${isDark(tester) ? 'dark' : 'light'}',
      keyboard: keyboard,
    );
  }

  /// The screen in the current theme, then in the other one (switched on
  /// this device only, then switched back).
  Future<void> both(String name, {bool keyboard = false}) async {
    _n++;
    final number = _n.toString().padLeft(2, '0');
    final container = appContainer(tester);
    final notifier = container.read(themePreferenceProvider.notifier);
    final before = container.read(themePreferenceProvider);
    final dark = isDark(tester);
    await _capture(
      '${number}_${name}_${dark ? 'dark' : 'light'}',
      keyboard: keyboard,
    );
    await notifier.setLocal(
      dark ? ThemePreference.light : ThemePreference.dark,
    );
    await settle(tester, const Duration(milliseconds: 500));
    await _capture(
      '${number}_${name}_${dark ? 'light' : 'dark'}',
      keyboard: keyboard,
    );
    await notifier.setLocal(before);
    await settle(tester, const Duration(milliseconds: 500));
  }
}

/// Step results with timings, printed as `E2E_STEP` lines for the report.
class StepLog {
  StepLog({this.onFail});

  /// Called with the step name when a step fails (for a screenshot).
  final Future<void> Function(String step)? onFail;

  final List<String> lines = [];
  final Stopwatch _total = Stopwatch()..start();

  Future<T> step<T>(String name, Future<T> Function() body) async {
    final watch = Stopwatch()..start();
    try {
      final result = await body();
      _record('PASS', name, watch);
      return result;
    } catch (_) {
      _record('FAIL', name, watch);
      try {
        await onFail?.call(name);
      } on Object catch (e) {
        debugPrint('E2E_FAIL_SHOT_FAILED $e');
      }
      rethrow;
    }
  }

  void _record(String status, String name, Stopwatch watch) {
    final line =
        'E2E_STEP $status ${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s $name';
    lines.add(line);
    debugPrint(line);
  }

  void finish() {
    debugPrint(
      'E2E_TOTAL ${(_total.elapsedMilliseconds / 1000).toStringAsFixed(1)}s',
    );
  }
}
