import 'package:expense_manager/core/accessibility/accessibility.dart';
import 'package:expense_manager/core/theme/app_palette.dart';
import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:expense_manager/core/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

const _focused = {WidgetState.focused};
const _selected = {WidgetState.selected};
const _selectedFocused = {WidgetState.selected, WidgetState.focused};

Map<String, Color> _pages(AppPalette p) => {
  'background': p.background,
  'surface': p.surface,
  'surfaceVariant': p.surfaceVariant,
  'surfaceElevated': p.surfaceElevated,
};

void _expectContrast(Color a, Color b, double min, String reason) {
  final ratio = contrastRatio(a, b);
  expect(
    ratio,
    greaterThanOrEqualTo(min),
    reason: '$reason: ${hex(a)} vs ${hex(b)} is ${ratio.toStringAsFixed(2)}:1',
  );
}

void _useKeyboardFocus() {
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  addTearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );
}

Widget _app(Widget home, ThemeMode mode) => MaterialApp(
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: mode,
  home: home,
);

void main() {
  for (final (name, theme, p, mode) in [
    ('light', AppTheme.light(), AppPalette.light, ThemeMode.light),
    ('dark', AppTheme.dark(), AppPalette.dark, ThemeMode.dark),
  ]) {
    group('$name focus indicator contrast', () {
      test('the ring is at least 3:1 against every page colour', () {
        for (final page in _pages(p).entries) {
          _expectContrast(p.focusRing, page.value, 3, 'focusRing/${page.key}');
        }
      });

      test('the gap separates filled controls from the ring', () {
        // A filled control's ring has the page on both sides, and the page
        // (the gap) must stand out from the fill itself.
        for (final fill in {'accent': p.accent, 'danger': p.danger}.entries) {
          for (final page in _pages(p).entries) {
            _expectContrast(fill.value, page.value, 3, '${fill.key} gap');
          }
        }
        final ring = AppTheme.focusRingSide(p);
        expect(ring.color, p.focusRing);
        expect(ring.width, AppTheme.focusRingWidth);
        expect(ring.strokeInset, closeTo(-AppTheme.focusRingGap, 1e-9));
        expect(
          ring.strokeOutset,
          closeTo(AppTheme.focusRingGap + AppTheme.focusRingWidth, 1e-9),
        );
      });

      test('the outlined focus border contrasts with chip fills', () {
        for (final fill in [
          p.surface,
          p.surfaceVariant,
          p.accentContainer,
          p.background,
        ]) {
          _expectContrast(p.focusRing, fill, 3, 'focus border');
        }
        expect(AppTheme.focusBorderSide(p).width, greaterThan(2));
      });

      test('marks drawn on the focus halo are readable', () {
        _expectContrast(p.textOnAccent, p.focusRing, 4.5, 'mark on halo');
      });

      test('a focused segment fill differs from its resting fill', () {
        for (final fill in [p.surface, p.accentContainer]) {
          _expectContrast(p.focusRing, fill, 3, 'segment fill');
        }
      });
    });

    group('$name focused states differ', () {
      test('filled, elevated, text and icon buttons draw the gap ring', () {
        for (final style in [
          theme.filledButtonTheme.style!,
          theme.elevatedButtonTheme.style!,
          theme.textButtonTheme.style!,
          theme.iconButtonTheme.style!,
        ]) {
          expect(style.side!.resolve(_focused), AppTheme.focusRingSide(p));
          expect(style.side!.resolve({}), isNot(AppTheme.focusRingSide(p)));
          expect(
            style.side!.resolve({WidgetState.focused, WidgetState.disabled}),
            isNot(AppTheme.focusRingSide(p)),
          );
        }
      });

      test('outlined buttons and chips thicken their border', () {
        final outlined = theme.outlinedButtonTheme.style!.side!;
        expect(outlined.resolve(_focused), AppTheme.focusBorderSide(p));
        expect(outlined.resolve({})!.color, p.accent);

        final chip = theme.chipTheme.side! as WidgetStateBorderSide;
        for (final base in [<WidgetState>{}, _selected]) {
          final rest = chip.resolve(base)!;
          final focus = chip.resolve({...base, WidgetState.focused})!;
          expect(focus, AppTheme.focusBorderSide(p));
          expect(focus.width, greaterThan(rest.width));
        }
      });

      test('the FAB shape carries the ring', () {
        final shape =
            theme.floatingActionButtonTheme.shape! as WidgetStateOutlinedBorder;
        expect(shape.resolve(_focused)!.side, AppTheme.focusRingSide(p));
        expect(shape.resolve({})!.side, BorderSide.none);
      });

      test('a focused segment is filled with the focus colour', () {
        final style = theme.segmentedButtonTheme.style!;
        for (final base in [<WidgetState>{}, _selected]) {
          final focus = {...base, WidgetState.focused};
          expect(style.backgroundColor!.resolve(focus), p.focusRing);
          expect(style.foregroundColor!.resolve(focus), p.textOnAccent);
          expect(style.backgroundColor!.resolve(base), isNot(p.focusRing));
        }
      });

      test('switches, checkboxes and radios show a solid halo', () {
        for (final overlay in [
          theme.switchTheme.overlayColor!,
          theme.checkboxTheme.overlayColor!,
          theme.radioTheme.overlayColor!,
        ]) {
          expect(overlay.resolve(_focused), p.focusRing);
          expect(overlay.resolve(_selectedFocused), p.focusRing);
          // Other states keep the Material defaults.
          expect(overlay.resolve({WidgetState.pressed}), isNull);
          expect(overlay.resolve({}), isNull);
        }
      });

      test('toggle marks are redrawn on the halo', () {
        final sw = theme.switchTheme;
        expect(sw.thumbColor!.resolve(_focused), p.textOnAccent);
        expect(sw.thumbColor!.resolve({}), isNot(p.textOnAccent));
        expect(sw.trackOutlineColor!.resolve(_focused), p.focusRing);
        expect(sw.trackOutlineColor!.resolve(_selectedFocused), p.textOnAccent);

        final box = theme.checkboxTheme;
        expect(box.fillColor!.resolve(_selectedFocused), p.textOnAccent);
        expect(box.fillColor!.resolve(_selected), p.accent);
        expect(box.checkColor!.resolve(_selectedFocused), p.focusRing);
        final side = box.side! as WidgetStateBorderSide;
        expect(side.resolve(_focused)!.color, p.textOnAccent);
        expect(side.resolve({})!.color, p.outline);
        expect(side.resolve(_selected), isNull);

        final radio = theme.radioTheme.fillColor!;
        expect(radio.resolve(_focused), p.textOnAccent);
        expect(radio.resolve(_selectedFocused), p.textOnAccent);
        expect(radio.resolve(_selected), p.accent);
      });

      test('a selected icon button gets a filled container', () {
        final style = theme.iconButtonTheme.style!;
        expect(style.backgroundColor!.resolve(_selected), p.accentContainer);
        expect(style.backgroundColor!.resolve({}), isNull);
        expect(style.foregroundColor!.resolve(_selected), p.onAccentContainer);
        expect(style.side!.resolve(_selected)!.color, p.accent);
        _expectContrast(
          p.onAccentContainer,
          p.accentContainer,
          4.5,
          'selected icon',
        );
        _expectContrast(p.accent, p.surface, 3, 'selected outline');
      });
    });

    group('$name focus in widgets', () {
      testWidgets('a focused FilledButton draws the ring', (tester) async {
        _useKeyboardFocus();
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: Center(
                child: FilledButton(onPressed: () {}, child: const Text('Go')),
              ),
            ),
            mode,
          ),
        );
        Material material() => tester.widget<Material>(
          find.descendant(
            of: find.byType(FilledButton),
            matching: find.byType(Material),
          ),
        );
        expect((material().shape! as OutlinedBorder).side, BorderSide.none);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(
          (material().shape! as OutlinedBorder).side,
          AppTheme.focusRingSide(p),
        );
      });

      testWidgets('a focused FAB draws the ring', (tester) async {
        _useKeyboardFocus();
        await tester.pumpWidget(
          _app(
            Scaffold(
              floatingActionButton: FloatingActionButton(
                tooltip: 'Add',
                onPressed: () {},
                child: const Icon(Icons.add),
              ),
            ),
            mode,
          ),
        );
        Material material() => tester.widget<Material>(
          find.descendant(
            of: find.byType(FloatingActionButton),
            matching: find.byType(Material),
          ),
        );
        expect((material().shape! as OutlinedBorder).side, BorderSide.none);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(
          (material().shape! as OutlinedBorder).side,
          AppTheme.focusRingSide(p),
        );
      });

      testWidgets('AppIconButton(selected) without selectedIcon is filled', (
        tester,
      ) async {
        Future<Color?> fill({required bool selected}) async {
          await tester.pumpWidget(
            _app(
              Scaffold(
                body: Center(
                  child: AppIconButton(
                    icon: Icons.filter_list,
                    tooltip: 'Filter',
                    selected: selected,
                    onPressed: () {},
                  ),
                ),
              ),
              mode,
            ),
          );
          await tester.pumpAndSettle();
          return tester
              .widget<Material>(
                find.descendant(
                  of: find.byType(IconButton),
                  matching: find.byType(Material),
                ),
              )
              .color;
        }

        expect(await fill(selected: true), p.accentContainer);
        final rest = await fill(selected: false);
        expect(rest == null || rest.a == 0, isTrue);
      });

      testWidgets('AppNavigationDestination outlines the focused tab', (
        tester,
      ) async {
        _useKeyboardFocus();
        await tester.pumpWidget(
          _app(
            Scaffold(
              bottomNavigationBar: NavigationBar(
                destinations: const [
                  AppNavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'Home',
                  ),
                  AppNavigationDestination(
                    icon: Icon(Icons.list_alt_outlined),
                    label: 'Expenses',
                  ),
                ],
              ),
            ),
            mode,
          ),
        );
        BoxDecoration decoration() =>
            tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: find.byType(FocusOutline).first,
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        expect(decoration().border, isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect((decoration().border! as Border).top.color, p.focusRing);
      });
    });
  }
}
