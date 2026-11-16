import 'dart:async';

import 'package:alchemist/alchemist.dart';
import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

import 'kit_gallery.dart';
import '../support/golden_clock.dart';

/// Alchemist golden gallery of the widget kit. Regenerate with
/// `flutter test --update-goldens test/design_system`.
void main() {
  useGoldenClock();
  unawaited(
    goldenTest(
      'widget kit renders in light and dark',
      fileName: 'kit_gallery',
      pumpBeforeTest: pumpOnce,
      builder: () => GoldenTestGroup(
        columns: 2,
        children: [
          for (final (name, theme) in [
            ('light', AppTheme.light()),
            ('dark', AppTheme.dark()),
          ])
            GoldenTestScenario(
              name: name,
              constraints: const BoxConstraints(maxWidth: 400),
              child: ThemedFrame(theme: theme, child: const KitGallery()),
            ),
        ],
      ),
    ),
  );

  unawaited(
    goldenTest(
      'widget kit fits 320dp at 200% text',
      fileName: 'kit_gallery_320_text2x',
      pumpBeforeTest: pumpOnce,
      builder: () => GoldenTestGroup(
        columns: 2,
        children: [
          for (final (name, theme) in [
            ('light', AppTheme.light()),
            ('dark', AppTheme.dark()),
          ])
            GoldenTestScenario.withTextScaleFactor(
              name: '$name 320dp x2.0',
              textScaler: const TextScaler.linear(2),
              constraints: const BoxConstraints(maxWidth: 320),
              child: ThemedFrame(theme: theme, child: const KitGallery()),
            ),
        ],
      ),
    ),
  );
}
