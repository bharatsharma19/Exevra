import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design_system/contrast.dart';

/// The assistant uses the app theme unchanged; every text role it draws
/// reaches WCAG AA on the surface it sits on.
void main() {
  final themes = {'light': AppTheme.light(), 'dark': AppTheme.dark()};

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    test('$name: every chat text role reaches 4.5:1', () {
      final s = theme.colorScheme;
      final page = theme.scaffoldBackgroundColor;
      final fill = Color.alphaBlend(
        theme.inputDecorationTheme.fillColor ?? s.surfaceContainerHighest,
        page,
      );
      final pairs = <String, (Color, Color)>{
        'user bubble': (s.onPrimaryContainer, s.primaryContainer),
        'error card': (s.onErrorContainer, s.errorContainer),
        'filled button': (s.onPrimary, s.primary),
        'text button on surface': (s.primary, s.surface),
        'text button on page': (s.primary, page),
        'link in a bubble': (s.primary, s.surfaceContainerHigh),
        'error text on surface': (s.error, s.surface),
        'error text on page': (s.error, page),
        'secondary text': (s.onSurfaceVariant, s.surface),
        'secondary text on page': (s.onSurfaceVariant, page),
        'hint': (theme.inputDecorationTheme.hintStyle!.color!, fill),
      };
      for (final MapEntry(key: label, value: (fg, bg)) in pairs.entries) {
        expect(
          contrastRatio(fg, bg),
          greaterThanOrEqualTo(4.5),
          reason: '$label: ${hex(fg)} on ${hex(bg)}',
        );
      }
    });
  }
}
