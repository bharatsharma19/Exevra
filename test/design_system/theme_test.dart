import 'package:expense_manager/core/theme/app_palette.dart';
import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:expense_manager/core/theme/system_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

void main() {
  for (final (name, theme, palette) in [
    ('light', AppTheme.light(), AppPalette.light),
    ('dark', AppTheme.dark(), AppPalette.dark),
  ]) {
    group('$name theme', () {
      test('is Material 3 with the palette attached', () {
        expect(theme.useMaterial3, isTrue);
        expect(theme.brightness, palette.brightness);
        expect(theme.extension<AppPalette>(), same(palette));
        expect(theme.scaffoldBackgroundColor, palette.background);
      });

      test('colour scheme comes from the tokens, not a seed', () {
        final s = theme.colorScheme;
        expect(s.primary, palette.accent);
        expect(s.onPrimary, palette.textOnAccent);
        expect(s.primaryContainer, palette.accentContainer);
        expect(s.error, palette.danger);
        expect(s.onError, palette.onDanger);
        expect(s.surface, palette.surface);
        expect(s.onSurface, palette.textPrimary);
        expect(s.onSurfaceVariant, palette.textSecondary);
        expect(s.outline, palette.outline);
        expect(s.inverseSurface, palette.inverseSurface);
        expect(s.surfaceTint, Colors.transparent);
      });

      test('system bars contrast with the theme', () {
        final style = theme.appBarTheme.systemOverlayStyle!;
        final icons = palette.isDark ? Brightness.light : Brightness.dark;
        expect(style.statusBarColor, Colors.transparent);
        expect(style.statusBarIconBrightness, icons);
        expect(style.statusBarBrightness, palette.brightness);
        expect(style.systemNavigationBarColor, palette.background);
        expect(style.systemNavigationBarIconBrightness, icons);
        expect(style, AppSystemUi.styleFor(palette));
      });

      test('snackbars float and are readable', () {
        final snack = theme.snackBarTheme;
        expect(snack.behavior, SnackBarBehavior.floating);
        expect(
          contrastRatio(snack.contentTextStyle!.color!, snack.backgroundColor!),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrastRatio(snack.actionTextColor!, snack.backgroundColor!),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('buttons and tiles keep 48dp targets', () {
        for (final style in [
          theme.elevatedButtonTheme.style!,
          theme.filledButtonTheme.style!,
          theme.outlinedButtonTheme.style!,
          theme.textButtonTheme.style!,
          theme.iconButtonTheme.style!,
        ]) {
          final min = style.minimumSize!.resolve({})!;
          expect(min.width, greaterThanOrEqualTo(48));
          expect(min.height, greaterThanOrEqualTo(48));
        }
        expect(theme.listTileTheme.minTileHeight, greaterThanOrEqualTo(48));
        expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
      });

      test('disabled buttons stay readable', () {
        final style = theme.elevatedButtonTheme.style!;
        const disabled = {WidgetState.disabled};
        final fg = style.foregroundColor!.resolve(disabled)!;
        final bg = style.backgroundColor!.resolve(disabled)!;
        expect(contrastRatio(fg, bg), greaterThanOrEqualTo(4.5));
      });

      test('primary button text and spinner colour contrast with fill', () {
        final style = theme.elevatedButtonTheme.style!;
        final fg = style.foregroundColor!.resolve({})!;
        final bg = style.backgroundColor!.resolve({})!;
        expect(contrastRatio(fg, bg), greaterThanOrEqualTo(4.5));
      });

      test('text theme uses the palette colours', () {
        expect(theme.textTheme.bodyLarge!.color, palette.textPrimary);
        expect(theme.textTheme.bodySmall!.color, palette.textSecondary);
      });
    });
  }

  test('legacy getters return the same themes', () {
    expect(AppTheme.lightTheme, same(AppTheme.light()));
    expect(AppTheme.darkTheme, same(AppTheme.dark()));
  });

  test('palette lerp and copyWith', () {
    final mid = AppPalette.light.lerp(AppPalette.dark, 0.5);
    expect(mid.brightness, Brightness.dark);
    expect(
      AppPalette.light.lerp(AppPalette.dark, 0).accent,
      AppPalette.light.accent,
    );
    expect(
      AppPalette.light.lerp(AppPalette.dark, 1).chart,
      AppPalette.dark.chart,
    );
    expect(AppPalette.light.lerp(null, 0.5), same(AppPalette.light));
    final changed = AppPalette.light.copyWith(accent: AppPalette.dark.accent);
    expect(changed.accent, AppPalette.dark.accent);
    expect(changed.surface, AppPalette.light.surface);
    expect(AppPalette.light.chartColor(9), AppPalette.light.chart[1]);
  });

  testWidgets('SystemUiRegion annotates the current theme style', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: const SystemUiRegion(child: SizedBox.expand()),
      ),
    );
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).last,
    );
    expect(region.value.statusBarIconBrightness, Brightness.light);
    expect(region.value.systemNavigationBarColor, AppPalette.dark.background);
  });
}
