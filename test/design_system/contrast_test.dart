import 'package:expense_manager/core/constants/app_constants.dart';
import 'package:expense_manager/core/theme/app_palette.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

/// A foreground/background pair with its required minimum ratio.
class _Pair {
  const _Pair(this.name, this.fg, this.bg, this.min);
  final String name;
  final Color fg;
  final Color bg;
  final double min;
  double get ratio => contrastRatio(fg, bg);
}

const _text = 4.5;
const _ui = 3.0;

Map<String, Color> _surfaces(AppPalette p) => {
  'background': p.background,
  'surface': p.surface,
  'surfaceVariant': p.surfaceVariant,
  'surfaceElevated': p.surfaceElevated,
};

/// Every token that may be drawn as text or as an icon on a surface.
Map<String, Color> _textTokens(AppPalette p) => {
  'textPrimary': p.textPrimary,
  'textSecondary': p.textSecondary,
  'textTertiary': p.textTertiary,
  'accent': p.accent,
  'secondary': p.secondary,
  'success': p.success,
  'warning': p.warning,
  'danger': p.danger,
  'info': p.info,
  'positiveAmount': p.positiveAmount,
  'negativeAmount': p.negativeAmount,
};

List<_Pair> _textOnSurfaces(AppPalette p) => [
  for (final t in _textTokens(p).entries)
    for (final s in _surfaces(p).entries)
      _Pair('${t.key} on ${s.key}', t.value, s.value, _text),
];

List<_Pair> _onColors(AppPalette p) => [
  _Pair('textOnAccent on accent', p.textOnAccent, p.accent, _text),
  _Pair('onSecondary on secondary', p.onSecondary, p.secondary, _text),
  _Pair('onSuccess on success', p.onSuccess, p.success, _text),
  _Pair('onWarning on warning', p.onWarning, p.warning, _text),
  _Pair('onDanger on danger', p.onDanger, p.danger, _text),
  _Pair('onInfo on info', p.onInfo, p.info, _text),
  _Pair(
    'onInverseSurface on inverseSurface',
    p.onInverseSurface,
    p.inverseSurface,
    _text,
  ),
  _Pair(
    'inverseAccent on inverseSurface',
    p.inverseAccent,
    p.inverseSurface,
    _text,
  ),
];

List<_Pair> _containers(AppPalette p) {
  final groups = <String, (Color, Color, Color)>{
    'accent': (p.accent, p.accentContainer, p.onAccentContainer),
    'secondary': (p.secondary, p.secondaryContainer, p.onSecondaryContainer),
    'success': (p.success, p.successContainer, p.onSuccessContainer),
    'warning': (p.warning, p.warningContainer, p.onWarningContainer),
    'danger': (p.danger, p.dangerContainer, p.onDangerContainer),
    'info': (p.info, p.infoContainer, p.onInfoContainer),
  };
  return [
    for (final g in groups.entries) ...[
      _Pair(
        'on${_cap(g.key)}Container on ${g.key}Container',
        g.value.$3,
        g.value.$2,
        _text,
      ),
      _Pair('${g.key} on ${g.key}Container', g.value.$1, g.value.$2, _text),
    ],
  ];
}

List<_Pair> _components(AppPalette p) => [
  for (final s in ['background', 'surface', 'surfaceVariant'])
    for (final c in {
      'outline': p.outline,
      'outlineStrong': p.outlineStrong,
      'focusRing': p.focusRing,
      'accent': p.accent,
    }.entries)
      _Pair('${c.key} vs $s', c.value, _surfaces(p)[s]!, _ui),
  for (var i = 0; i < p.chart.length; i++)
    _Pair('chart[$i] vs surface', p.chart[i], p.surface, _ui),
];

String _cap(String s) => s[0].toUpperCase() + s.substring(1);

String _table(List<_Pair> pairs) {
  final buffer = StringBuffer()
    ..writeln(
      '${'pair'.padRight(48)} ${'fg'.padRight(8)} ${'bg'.padRight(8)} '
      'ratio   min',
    );
  for (final p in pairs) {
    buffer.writeln(
      '${p.name.padRight(48)} ${hex(p.fg)} ${hex(p.bg)} '
      '${p.ratio.toStringAsFixed(2).padLeft(5)}  ${p.min}',
    );
  }
  return buffer.toString();
}

void _expectPairs(List<_Pair> pairs) {
  final failing = pairs.where((p) => p.ratio < p.min).toList();
  expect(
    failing,
    isEmpty,
    reason: 'Contrast below WCAG minimum:\n${_table(failing)}',
  );
}

void main() {
  test('contrast helper matches known WCAG values', () {
    expect(
      contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
      closeTo(21, 0.01),
    );
    expect(
      contrastRatio(const Color(0xFF0E7490), const Color(0xFFFFFFFF)),
      closeTo(5.36, 0.01),
    );
    expect(
      contrastRatio(const Color(0xFF00E5FF), const Color(0xFFFFFFFF)),
      closeTo(1.54, 0.01),
    );
  });

  for (final (name, palette) in [
    ('light', AppPalette.light),
    ('dark', AppPalette.dark),
  ]) {
    group('$name palette', () {
      test('text tokens reach 4.5:1 on every surface', () {
        _expectPairs(_textOnSurfaces(palette));
      });

      test('on-colours reach 4.5:1 on their fills', () {
        _expectPairs(_onColors(palette));
      });

      test('semantic tokens reach 4.5:1 on their containers', () {
        _expectPairs(_containers(palette));
      });

      test('component boundaries and chart colours reach 3:1', () {
        _expectPairs(_components(palette));
      });

      test('chart has 8 mutually distinguishable colours', () {
        expect(palette.chart, hasLength(8));
        final close = <String>[];
        for (var i = 0; i < palette.chart.length; i++) {
          for (var j = i + 1; j < palette.chart.length; j++) {
            final d = deltaE(palette.chart[i], palette.chart[j]);
            if (d < 20) {
              close.add(
                'chart[$i] ${hex(palette.chart[i])} vs chart[$j] '
                '${hex(palette.chart[j])}: Delta E ${d.toStringAsFixed(1)}',
              );
            }
          }
        }
        expect(close, isEmpty, reason: close.join('\n'));
      });

      test('chart order survives deuteranopia and protanopia', () {
        // Neighbouring series (including the wrap from the last to the
        // first) and the first five series must stay apart for the most
        // common colour-vision deficiencies.
        final chart = palette.chart;
        final pairs = {
          for (var i = 0; i < 5; i++)
            for (var j = i + 1; j < 5; j++) (i, j),
          for (var i = 0; i < chart.length; i++) (i, (i + 1) % chart.length),
        };
        final close = <String>[];
        for (final (i, j) in pairs) {
          for (final type in Cvd.values) {
            final d = deltaE(
              simulateCvd(chart[i], type),
              simulateCvd(chart[j], type),
            );
            if (d < 12) {
              close.add(
                '${type.name}: chart[$i] ${hex(chart[i])} vs chart[$j] '
                '${hex(chart[j])}: Delta E ${d.toStringAsFixed(1)}',
              );
            }
          }
        }
        expect(close, isEmpty, reason: close.join('\n'));
      });

      test('onChart reaches 4.5:1 on every chart and category colour', () {
        _expectPairs([
          for (var i = 0; i < palette.chart.length; i++)
            _Pair(
              'onChart on chart[$i]',
              palette.onChart,
              palette.chart[i],
              _text,
            ),
          for (final c in palette.categories.entries)
            _Pair('onChart on ${c.key}', palette.onChart, c.value, _text),
          _Pair(
            'onChart on categoryFallback',
            palette.onChart,
            palette.categoryFallback,
            _text,
          ),
        ]);
      });

      test('category colours reach 3:1 and cover every category', () {
        _expectPairs([
          for (final c in palette.categories.entries)
            for (final s in ['background', 'surface', 'surfaceVariant'])
              _Pair('${c.key} vs $s', c.value, _surfaces(palette)[s]!, _ui),
          _Pair(
            'categoryFallback vs surface',
            palette.categoryFallback,
            palette.surface,
            _ui,
          ),
        ]);
        for (final category in AppConstants.categories) {
          expect(
            palette.categories.containsKey(category.name),
            isTrue,
            reason: 'No palette colour for ${category.name}',
          );
        }
        expect(palette.categoryColor('food'), palette.categories['Food']);
        expect(palette.categoryColor('Unknown'), palette.categoryFallback);
      });

      test('selected navigation and focus indicators reach 3:1', () {
        // The navigation indicator outline and selected icon/label colour,
        // the selected list tile outline and the focus ring all sit on the
        // surface or page background.
        _expectPairs([
          for (final s in ['background', 'surface', 'surfaceElevated'])
            _Pair('accent vs $s', palette.accent, _surfaces(palette)[s]!, _ui),
          _Pair(
            'accent vs accentContainer',
            palette.accent,
            palette.accentContainer,
            _ui,
          ),
          for (final s in ['background', 'surface', 'surfaceElevated'])
            _Pair(
              'focusRing vs $s',
              palette.focusRing,
              _surfaces(palette)[s]!,
              _ui,
            ),
        ]);
      });

      test('all palette colours are opaque except the scrim', () {
        final translucent = [
          for (final c in [
            ..._textTokens(palette).values,
            ..._surfaces(palette).values,
          ])
            if (c.a < 1) hex(c),
        ];
        expect(translucent, isEmpty);
        expect(palette.scrim.a, lessThan(1));
      });
    });
  }

  test('bright cyan is never a text colour in the light palette', () {
    const brightCyan = Color(0xFF00E5FF);
    for (final c in [
      ..._textTokens(AppPalette.light).values,
      AppPalette.light.focusRing,
    ]) {
      expect(c, isNot(brightCyan));
    }
    expect(AppPalette.light.accent, const Color(0xFF0E7490));
    expect(AppPalette.dark.accent, brightCyan);
  });
}
