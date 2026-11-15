// Every themed control keeps its text at 4.5:1 and its icons at 3:1 against
// what is painted behind them, in every interactive state.
//
// Each control is pumped, driven into a real state (keyboard focus, mouse
// hover, a held press, selection) and measured from the widget tree: the
// foreground is the resolved DefaultTextStyle / IconTheme at the label or
// icon, and the background is the stack Flutter paints under it (Materials,
// an Ink decoration, a navigation indicator, then the ink highlight and
// splash of that state), blended over each page colour.
import 'package:expense_manager/core/theme/app_palette.dart';
import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

const _label = 'Label';
const _subtitle = 'Subtitle';
const _icon = Icons.star_outline;

/// Interactive states measured for every control (null is the resting one).
const _states = <WidgetState?>[
  null,
  WidgetState.hovered,
  WidgetState.focused,
  WidgetState.pressed,
];

const _highlightable = {
  WidgetState.focused,
  WidgetState.hovered,
  WidgetState.pressed,
};

enum _Kind {
  text(4.5),
  icon(3);

  const _Kind(this.minimum);

  final double minimum;
}

typedef _Target = (_Kind, Finder Function());

Finder _text() => find.text(_label);
Finder _subtitleText() => find.text(_subtitle);
Finder _iconFinder() => find.byIcon(_icon);
Finder _checkFinder() => find.byIcon(Icons.check);

const _Target _textTarget = (_Kind.text, _text);
const _Target _iconTarget = (_Kind.icon, _iconFinder);

class _Case {
  const _Case(
    this.name,
    this.build, {
    this.targets = const [_textTarget],
    this.interactive = true,
  });

  final String name;
  final Widget Function() build;
  final List<_Target> targets;

  /// False for display-only controls, which only have the resting state.
  final bool interactive;
}

void _noop() {}

const _iconWidget = Icon(_icon);
const _labelWidget = Text(_label);

List<_Case> _cases() => [
  _Case(
    'ElevatedButton',
    () => const ElevatedButton(onPressed: _noop, child: _labelWidget),
  ),
  _Case(
    'ElevatedButton.icon',
    () => ElevatedButton.icon(
      onPressed: _noop,
      icon: _iconWidget,
      label: _labelWidget,
    ),
    targets: const [_textTarget, _iconTarget],
  ),
  _Case(
    'FilledButton',
    () => const FilledButton(onPressed: _noop, child: _labelWidget),
  ),
  _Case(
    'FilledButton.icon',
    () => FilledButton.icon(
      onPressed: _noop,
      icon: _iconWidget,
      label: _labelWidget,
    ),
    targets: const [_textTarget, _iconTarget],
  ),
  _Case(
    'FilledButton.tonal',
    () => const FilledButton.tonal(onPressed: _noop, child: _labelWidget),
  ),
  _Case(
    'OutlinedButton',
    () => const OutlinedButton(onPressed: _noop, child: _labelWidget),
  ),
  _Case(
    'OutlinedButton.icon',
    () => OutlinedButton.icon(
      onPressed: _noop,
      icon: _iconWidget,
      label: _labelWidget,
    ),
    targets: const [_textTarget, _iconTarget],
  ),
  _Case(
    'TextButton',
    () => const TextButton(onPressed: _noop, child: _labelWidget),
  ),
  _Case(
    'TextButton.icon',
    () => TextButton.icon(
      onPressed: _noop,
      icon: _iconWidget,
      label: _labelWidget,
    ),
    targets: const [_textTarget, _iconTarget],
  ),
  for (final selected in [null, false, true]) ...[
    _Case(
      'IconButton (selected: $selected)',
      () =>
          IconButton(onPressed: _noop, isSelected: selected, icon: _iconWidget),
      targets: const [_iconTarget],
    ),
    _Case(
      'IconButton.filled (selected: $selected)',
      () => IconButton.filled(
        onPressed: _noop,
        isSelected: selected,
        icon: _iconWidget,
      ),
      targets: const [_iconTarget],
    ),
    _Case(
      'IconButton.filledTonal (selected: $selected)',
      () => IconButton.filledTonal(
        onPressed: _noop,
        isSelected: selected,
        icon: _iconWidget,
      ),
      targets: const [_iconTarget],
    ),
    _Case(
      'IconButton.outlined (selected: $selected)',
      () => IconButton.outlined(
        onPressed: _noop,
        isSelected: selected,
        icon: _iconWidget,
      ),
      targets: const [_iconTarget],
    ),
  ],
  _Case(
    'FloatingActionButton',
    () => const FloatingActionButton(
      heroTag: null,
      onPressed: _noop,
      child: _iconWidget,
    ),
    targets: const [_iconTarget],
  ),
  _Case(
    'FloatingActionButton.small',
    () => const FloatingActionButton.small(
      heroTag: null,
      onPressed: _noop,
      child: _iconWidget,
    ),
    targets: const [_iconTarget],
  ),
  _Case(
    'FloatingActionButton.extended',
    () => const FloatingActionButton.extended(
      heroTag: null,
      onPressed: _noop,
      icon: _iconWidget,
      label: _labelWidget,
    ),
    targets: const [_textTarget, _iconTarget],
  ),
  _Case('Chip', () => const Chip(label: _labelWidget), interactive: false),
  _Case(
    'ActionChip',
    () => const ActionChip(label: _labelWidget, onPressed: _noop),
  ),
  for (final selected in [false, true]) ...[
    _Case(
      'FilterChip (selected: $selected)',
      () => FilterChip(
        label: _labelWidget,
        selected: selected,
        onSelected: (_) {},
      ),
    ),
    _Case(
      'ChoiceChip (selected: $selected)',
      () => ChoiceChip(
        label: _labelWidget,
        selected: selected,
        onSelected: (_) {},
      ),
    ),
  ],
  for (final selected in [false, true])
    _Case(
      'SegmentedButton segment (selected: $selected)',
      () => SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: _labelWidget, icon: _iconWidget),
          ButtonSegment(value: 1, label: Text('Other')),
        ],
        selected: {selected ? 0 : 1},
        onSelectionChanged: (_) {},
      ),
      // A selected segment shows a check mark in place of its icon.
      targets: selected
          ? const [_textTarget, (_Kind.icon, _checkFinder)]
          : const [_textTarget, _iconTarget],
    ),
  for (final selected in [false, true])
    _Case(
      'NavigationBar destination (selected: $selected)',
      () => NavigationBar(
        selectedIndex: selected ? 0 : 1,
        onDestinationSelected: (_) {},
        destinations: const [
          NavigationDestination(icon: _iconWidget, label: _label),
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'Other',
          ),
        ],
      ),
      targets: const [_textTarget, _iconTarget],
    ),
  for (final selected in [false, true])
    _Case(
      'ListTile (selected: $selected)',
      () => ListTile(
        selected: selected,
        onTap: _noop,
        leading: _iconWidget,
        title: _labelWidget,
        subtitle: const Text(_subtitle),
      ),
      targets: const [_textTarget, _iconTarget, (_Kind.text, _subtitleText)],
    ),
];

/// Long enough for state colour transitions (Material animates its text
/// style for 200ms), short of a long press (500ms).
const _settle = Duration(milliseconds: 300);

/// Applies a state change (focus lands one frame after it is requested,
/// the control rebuilds on the next), then lets its colour transitions run.
Future<void> _settleState(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(_settle);
}

/// Puts the control under [target] into [state] for real.
Future<TestGesture?> _drive(
  WidgetTester tester,
  Finder target,
  WidgetState state,
) async {
  final center = tester.getCenter(target);
  switch (state) {
    case WidgetState.focused:
      final node = Focus.of(tester.element(target))..requestFocus();
      await _settleState(tester);
      expect(node.hasPrimaryFocus, isTrue, reason: 'focus did not land');
      return null;
    case WidgetState.hovered:
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: center);
      await _settleState(tester);
      return mouse;
    case WidgetState.pressed:
      final finger = await tester.startGesture(center);
      await _settleState(tester);
      return finger;
    default:
      throw ArgumentError.value(state);
  }
}

Color? _materialColor(Material m, ThemeData theme) {
  if (m.type == MaterialType.transparency) return null;
  return m.color ??
      (m.type == MaterialType.card ? theme.cardColor : theme.canvasColor);
}

Color? _decorationColor(Decoration? d) => switch (d) {
  BoxDecoration(:final color) => color,
  ShapeDecoration(:final color) => color,
  _ => null,
};

/// The colours painted under [target] (bottom first), excluding the page.
List<Color> _layers(
  WidgetTester tester,
  Finder target,
  WidgetState? state,
  ThemeData theme,
) {
  final layers = <Color>[];
  final inkFinder = find
      .ancestor(
        of: target,
        matching: find.byWidgetPredicate((w) => w is InkResponse),
      )
      .first;
  // Every Material from the outermost to the nearest one paints in order.
  final materials = tester.widgetList<Material>(
    find.ancestor(of: target, matching: find.byType(Material)),
  );
  for (final m in materials.toList().reversed) {
    final color = _materialColor(m, theme);
    if (color != null) layers.add(color);
  }
  // Ink decorations inside the ink response (chip and tile fills).
  final insideInk = tester
      .widgetList<Ink>(
        find.descendant(of: inkFinder, matching: find.byType(Ink)),
      )
      .toSet();
  final inks = tester.widgetList<Ink>(
    find.ancestor(of: target, matching: find.byType(Ink)),
  );
  for (final ink in inks.toList().reversed) {
    if (!insideInk.contains(ink)) continue;
    final color = _decorationColor(ink.decoration);
    if (color != null) layers.add(color);
  }
  // A navigation destination draws its icon on the indicator, and confines
  // its ink to the indicator, so the label below never gets a state layer.
  var inked = true;
  final destination = find.ancestor(
    of: target,
    matching: find.byType(NavigationDestination),
  );
  if (destination.evaluate().isNotEmpty) {
    final isIcon = tester.widget(target) is Icon;
    inked = isIcon;
    final indicator = tester.widget<NavigationIndicator>(
      find.descendant(
        of: destination.first,
        matching: find.byType(NavigationIndicator),
      ),
    );
    if (isIcon && indicator.animation.value > 0.99) {
      layers.add(indicator.color ?? theme.colorScheme.secondaryContainer);
    }
  }
  if (state != null && inked) {
    final ink = tester.widget<InkResponse>(inkFinder);
    final rest = (ink.statesController?.value ?? const <WidgetState>{})
        .difference(_highlightable);
    Color? overlay(WidgetState s) => ink.overlayColor?.resolve({...rest, s});
    switch (state) {
      case WidgetState.focused:
        layers.add(overlay(state) ?? ink.focusColor ?? theme.focusColor);
      case WidgetState.hovered:
        layers.add(overlay(state) ?? ink.hoverColor ?? theme.hoverColor);
      case WidgetState.pressed:
        // The pressed highlight, then the splash on top of it.
        layers
          ..add(overlay(state) ?? ink.highlightColor ?? theme.highlightColor)
          ..add(overlay(state) ?? ink.splashColor ?? theme.splashColor);
      default:
    }
  }
  return layers;
}

Color _foreground(WidgetTester tester, _Kind kind, Finder finder) {
  final element = tester.element(finder);
  if (kind == _Kind.text) {
    final widget = element.widget as Text;
    final style = DefaultTextStyle.of(element).style.merge(widget.style);
    // Text with no colour is painted in the engine default, white.
    expect(style.color, isNotNull, reason: 'label has no resolved colour');
    expect(style.fontSize, isNotNull, reason: 'label has no resolved size');
    return style.color!;
  }
  final widget = element.widget as Icon;
  final color = widget.color ?? IconTheme.of(element).color;
  expect(color, isNotNull, reason: 'icon has no resolved colour');
  return color!;
}

Color _over(List<Color> layers, Color page) =>
    layers.fold(page, (below, layer) => Color.alphaBlend(layer, below));

void main() {
  for (final (name, theme, p) in [
    ('light', AppTheme.light(), AppPalette.light),
    ('dark', AppTheme.dark(), AppPalette.dark),
  ]) {
    final pages = {
      'background': p.background,
      'surface': p.surface,
      'surfaceVariant': p.surfaceVariant,
      'surfaceElevated': p.surfaceElevated,
    };
    group('$name theme state contrast:', () {
      for (final c in _cases()) {
        for (final state in c.interactive ? _states : const [null]) {
          testWidgets('${c.name} ${state?.name ?? 'resting'}', (tester) async {
            FocusManager.instance.highlightStrategy =
                FocusHighlightStrategy.alwaysTraditional;
            addTearDown(
              () => FocusManager.instance.highlightStrategy =
                  FocusHighlightStrategy.automatic,
            );
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: Material(
                    type: MaterialType.transparency,
                    child: Center(child: c.build()),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final gesture = state == null
                ? null
                : await _drive(tester, c.targets.first.$2(), state);

            final failures = <String>[];
            for (final (kind, finder) in c.targets) {
              final fg = _foreground(tester, kind, finder());
              final layers = _layers(tester, finder(), state, theme);
              for (final page in pages.entries) {
                final bg = _over(layers, page.value);
                final ratio = contrastRatio(fg, bg);
                if (ratio < kind.minimum) {
                  failures.add(
                    '${kind.name} on ${page.key}: ${hex(fg)} vs ${hex(bg)} '
                    'is ${ratio.toStringAsFixed(2)}:1 '
                    '(needs ${kind.minimum}:1)',
                  );
                }
              }
            }

            if (state == WidgetState.pressed) await gesture!.up();
            if (state == WidgetState.hovered) await gesture!.removePointer();
            await tester.pumpAndSettle();
            expect(failures, isEmpty);
          });
        }
      }
    });
  }
}
