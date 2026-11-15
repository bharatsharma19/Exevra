import 'package:expense_manager/core/accessibility/accessibility.dart';
import 'package:expense_manager/core/theme/app_palette.dart';
import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:expense_manager/core/widgets/widgets.dart';
import 'package:expense_manager/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

Widget _app(
  Widget home, {
  ThemeMode mode = ThemeMode.light,
  bool withHost = false,
  double? textScale,
}) => MaterialApp(
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: mode,
  scaffoldMessengerKey: rootScaffoldMessengerKey,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) {
    var result = child!;
    if (withHost) result = SnackbarHost(child: result);
    if (textScale != null) {
      result = MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: result,
      );
    }
    return result;
  },
  home: home,
);

void _setView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Rect _snackRect(WidgetTester tester) => tester.getRect(
  find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)),
);

void main() {
  testWidgets('ConfirmDialog fits 320x640 at 200% text', (tester) async {
    _setView(tester, const Size(320, 640));
    await tester.pumpWidget(
      _app(
        textScale: 2,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showConfirmDialog(
                context,
                title: 'Delete this expense permanently?',
                message: 'This removes it for everyone in the group. ' * 3,
                confirmLabel: 'Delete expense',
                destructive: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Both actions stay reachable.
    await tester.ensureVisible(find.text('Delete expense'));
    expect(find.text('Cancel').hitTestable(), findsOneWidget);
    expect(find.text('Delete expense').hitTestable(), findsOneWidget);
  });

  group('AppSnackbar actions', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final kind in AppSnackbarKind.values) {
        testWidgets('${kind.name} action reaches 4.5:1 ($mode)', (
          tester,
        ) async {
          await tester.pumpWidget(
            _app(mode: mode, withHost: true, const Scaffold()),
          );
          AppSnackbar.show(
            'Expense saved',
            kind: kind,
            action: SnackBarAction(label: 'View', onPressed: () {}),
          );
          await tester.pumpAndSettle();
          final palette = mode == ThemeMode.dark
              ? AppPalette.dark
              : AppPalette.light;
          final background = tester
              .widget<SnackBar>(find.byType(SnackBar))
              .backgroundColor!;
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text('View'),
          );
          final color = paragraph.text.style!.color!;
          expect(
            contrastRatio(color, background),
            greaterThanOrEqualTo(4.5),
            reason: '${hex(color)} on ${hex(background)}',
          );
          expect(background, isNot(palette.inverseSurface));
        });
      }
    }
  });

  testWidgets('OfflineBanner toggles cleanly under reduced motion', (
    tester,
  ) async {
    var visible = false;
    late StateSetter setOuter;
    await tester.pumpWidget(
      _app(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setOuter = setState;
                return Column(children: [OfflineBanner(visible: visible)]);
              },
            ),
          ),
        ),
      ),
    );
    for (final next in [true, false, true]) {
      setOuter(() => visible = next);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text("You're offline"), next ? findsOneWidget : findsNothing);
    }
  });

  testWidgets('LoadingButton wraps a long label at 320dp and 200% text', (
    tester,
  ) async {
    _setView(tester, const Size(320, 640));
    await tester.pumpWidget(
      _app(
        textScale: 2,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: LoadingButton(
              label: 'Save and continue to the next step',
              icon: Icons.check,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Save and continue to the next step'),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
  });

  testWidgets('a tappable AppCard is at least 48dp tall', (tester) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Column(
            children: [
              AppCard(
                onTap: () {},
                padding: EdgeInsets.zero,
                child: const Text('c'),
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(AppCard)).height,
      greaterThanOrEqualTo(48),
    );
  });

  group('SnackbarHost placement', () {
    testWidgets('lifts snackbars above the keyboard over a sheet', (
      tester,
    ) async {
      _setView(tester, const Size(800, 600));
      await tester.pumpWidget(
        _app(
          withHost: true,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const Padding(
                    padding: EdgeInsets.all(16),
                    child: TextField(autofocus: true),
                  ),
                ),
                child: const Text('sheet'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('sheet'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();

      AppSnackbar.showError('Enter an amount');
      await tester.pumpAndSettle();
      expect(_snackRect(tester).bottom, lessThanOrEqualTo(300));
    });

    testWidgets('keeps snackbars clear of a SnackbarClearance nav bar', (
      tester,
    ) async {
      _setView(tester, const Size(800, 600));
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: AppTheme.light(),
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          builder: (context, child) => SnackbarHost(child: child!),
          home: Scaffold(
            floatingActionButton: FloatingActionButton(
              onPressed: () {},
              child: const Icon(Icons.add),
            ),
            bottomNavigationBar: SnackbarClearance(
              child: NavigationBar(
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
                  NavigationDestination(
                    icon: Icon(Icons.settings),
                    label: 'Settings',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      AppSnackbar.showSuccess('Expense saved');
      await tester.pumpAndSettle();
      final nav = tester.getRect(find.byType(NavigationBar));
      expect(_snackRect(tester).overlaps(nav), isFalse);

      // On a pushed page without the bar, the snackbar drops back down.
      navigator.currentState!
          .push(MaterialPageRoute<void>(builder: (_) => const Scaffold()))
          .ignore();
      await tester.pumpAndSettle();
      AppSnackbar.showSuccess('Saved again');
      await tester.pumpAndSettle();
      expect(_snackRect(tester).bottom, greaterThan(nav.top));
    });
  });

  group('AmountField', () {
    test('formatter keeps digits and two decimals', () {
      final f = AmountInputFormatter();
      TextEditingValue edit(String old, String next) => f.formatEditUpdate(
        TextEditingValue(text: old),
        TextEditingValue(text: next),
      );
      expect(edit('12', '12.').text, '12.');
      expect(edit('12.5', '12.50').text, '12.50');
      expect(edit('12.50', '12.505').text, '12.50');
      expect(edit('12', '12a').text, '12');
      expect(edit('12', '12,5').text, '12.5');
      expect(edit('1.2', '1.2.').text, '1.2');
      expect(AmountField.parse('1,250.50'), 1250.5);
      expect(AmountField.parse(''), isNull);
      expect(AmountField.parse('.'), isNull);
    });

    testWidgets('uses a decimal keyboard, prefix and inline error', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: AmountField(
              controller: controller,
              label: 'Amount',
              currencySymbol: '₹',
              errorText: 'Enter an amount',
            ),
          ),
        ),
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(
        field.keyboardType,
        const TextInputType.numberWithOptions(decimal: true),
      );
      expect(field.decoration!.prefixText, '₹ ');
      expect(find.text('Enter an amount'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '99.999');
      expect(controller.text, isNot('99.999'));
      expect(find.bySemanticsLabel(RegExp('Amount')), findsWidgets);
    });
  });

  testWidgets('AppPasswordField toggles with a labelled button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const Scaffold(body: AppPasswordField(label: 'Password'))),
    );
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, true);
    expect(find.byTooltip('Show password'), findsOneWidget);
    expect(tester.getSize(find.byType(IconButton)).width, 48);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, false);
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  testWidgets('AppAvatar shows initials and reads the name', (tester) async {
    expect(AppAvatar.initialsOf('Priya  Sharma'), 'PS');
    expect(AppAvatar.initialsOf('arjun'), 'A');
    expect(AppAvatar.initialsOf('  '), '?');
    expect(
      AppAvatar.colorIndexOf('Priya', 5),
      AppAvatar.colorIndexOf('priya', 5),
    );
    await tester.pumpWidget(
      _app(const Scaffold(body: AppAvatar(name: 'Priya Sharma'))),
    );
    expect(find.text('PS'), findsOneWidget);
    expect(find.bySemanticsLabel('Priya Sharma'), findsOneWidget);
  });

  testWidgets('a guarded showAppSheet asks before a barrier tap closes it', (
    tester,
  ) async {
    _setView(tester, const Size(400, 800));
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAppSheet<void>(
                context: context,
                guarded: true,
                builder: (_) => const UnsavedChangesGuard(
                  hasChanges: true,
                  child: SizedBox(height: 200, child: Text('form')),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(sheet.enableDrag, isFalse);
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('form'), findsNothing);
  });

  group('focus and selection', () {
    testWidgets('a focused AppCard draws the focus ring', (tester) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: AppCard(onTap: () {}, child: const Text('card')),
          ),
        ),
      );
      Decoration decoration() => tester
          .widget<DecoratedBox>(
            find
                .descendant(
                  of: find.byType(FocusOutline),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          )
          .decoration;
      expect((decoration() as BoxDecoration).border, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final border = (decoration() as BoxDecoration).border! as Border;
      expect(border.top.color, AppPalette.light.focusRing);
    });

    test('button themes draw a focus ring outside the control', () {
      final theme = AppTheme.light();
      for (final style in [
        theme.filledButtonTheme.style!,
        theme.elevatedButtonTheme.style!,
        theme.textButtonTheme.style!,
        theme.outlinedButtonTheme.style!,
        theme.iconButtonTheme.style!,
      ]) {
        final side = style.side!.resolve({WidgetState.focused})!;
        expect(side.color, AppPalette.light.focusRing);
        // Outside the control: the outlined border sits on its edge, the
        // other buttons' ring leaves a gap (see focus_indicator_test).
        expect(
          side.strokeAlign,
          greaterThanOrEqualTo(BorderSide.strokeAlignOutside),
        );
      }
    });

    for (final (name, theme, palette) in [
      ('light', AppTheme.light(), AppPalette.light),
      ('dark', AppTheme.dark(), AppPalette.dark),
    ]) {
      test('navigation selection does not rely on the fill ($name)', () {
        final nav = theme.navigationBarTheme;
        final shape = nav.indicatorShape! as StadiumBorder;
        expect(shape.side.color, palette.accent);
        final selected = {WidgetState.selected};
        expect(nav.iconTheme!.resolve(selected)!.color, palette.accent);
        final label = nav.labelTextStyle!.resolve(selected)!;
        final unselected = nav.labelTextStyle!.resolve({})!;
        expect(label.color, palette.accent);
        expect(
          label.fontWeight!.value - unselected.fontWeight!.value,
          greaterThanOrEqualTo(300),
        );
      });
    }

    testWidgets('a selected AppListTile has an accent outline', (tester) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: AppListTile(title: 'Groceries', selected: true, onTap: () {}),
          ),
        ),
      );
      final shape =
          tester.widget<ListTile>(find.byType(ListTile)).shape!
              as RoundedRectangleBorder;
      expect(shape.side.color, AppPalette.light.accent);
    });
  });

  testWidgets('GlassCard blurs only when asked', (tester) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < 3; i++)
                GlassCard(onTap: () {}, child: Text('row $i')),
              const GlassCard(blurSigma: 12, child: Text('hero')),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
    await tester.tap(find.text('row 0'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}
