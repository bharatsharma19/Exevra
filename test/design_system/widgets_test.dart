import 'package:expense_manager/core/accessibility/accessibility.dart';
import 'package:expense_manager/core/theme/app_palette.dart';
import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:expense_manager/core/widgets/widgets.dart';
import 'package:expense_manager/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_gallery.dart';

Widget _app(
  Widget home, {
  ThemeMode mode = ThemeMode.light,
  bool withHost = false,
}) => MaterialApp(
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: mode,
  scaffoldMessengerKey: rootScaffoldMessengerKey,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: withHost ? (context, child) => SnackbarHost(child: child!) : null,
  home: home,
);

void main() {
  group('l10n', () {
    testWidgets('falls back to English without the delegate', (tester) async {
      late String retry;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              retry = context.l10n.retry;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(retry, 'Retry');
    });
  });

  group('LoadingButton', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('spinner uses the foreground colour ($mode)', (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: LoadingButton(
                label: 'Save',
                isLoading: true,
                onPressed: () => taps++,
              ),
            ),
            mode: mode,
          ),
        );
        final palette = mode == ThemeMode.dark
            ? AppPalette.dark
            : AppPalette.light;
        final spinner = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        );
        expect(spinner.color, palette.textOnAccent);
        await tester.tap(find.text('Save'), warnIfMissed: false);
        expect(taps, 0);
        final material = tester.widget<Material>(
          find.descendant(
            of: find.byType(FilledButton),
            matching: find.byType(Material),
          ),
        );
        expect(material.color, palette.accent);
      });
    }

    testWidgets('fires when not loading', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: LoadingButton(label: 'Save', onPressed: () => taps++),
          ),
        ),
      );
      await tester.tap(find.text('Save'));
      expect(taps, 1);
      expect(
        tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(48),
      );
    });
  });

  group('showConfirmDialog', () {
    Future<bool?> run(WidgetTester tester, String button) async {
      bool? result;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => result = await showConfirmDialog(
                  context,
                  title: 'Delete expense?',
                  message: 'This cannot be undone.',
                  confirmLabel: 'Delete',
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
      expect(find.text('Delete expense?'), findsOneWidget);
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('confirm resolves true', (tester) async {
      expect(await run(tester, 'Delete'), isTrue);
    });

    testWidgets('cancel resolves false', (tester) async {
      expect(await run(tester, 'Cancel'), isFalse);
    });
  });

  group('snackbars', () {
    testWidgets('undo snackbar shows above a modal sheet and reports undo', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          withHost: true,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const SizedBox(height: 200),
                ),
                child: const Text('sheet'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('sheet'));
      await tester.pumpAndSettle();

      final undone = showUndoSnackbar('Expense deleted');
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SnackbarHost),
          matching: find.byType(SnackBar),
        ),
        findsOneWidget,
      );
      // The tap reaches Undo instead of the sheet's modal barrier.
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(await undone, isTrue);
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('undo snackbar resolves false when it times out', (
      tester,
    ) async {
      await tester.pumpWidget(_app(withHost: true, const Scaffold()));
      final undone = showUndoSnackbar(
        'Expense deleted',
        duration: const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(await undone, isFalse);
    });

    testWidgets('kinds announce their tone', (tester) async {
      await tester.pumpWidget(_app(withHost: true, const Scaffold()));
      AppSnackbar.showError('Could not save');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Error. Could not save'), findsOneWidget);
    });

    testWidgets('is a no-op without a mounted messenger', (tester) async {
      await tester.pumpWidget(const SizedBox());
      expect(AppSnackbar.showInfo('hi'), isNull);
      expect(await showUndoSnackbar('hi'), isFalse);
    });
  });

  group('UnsavedChangesGuard', () {
    testWidgets('asks before leaving and pops on discard', (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: AppTheme.light(),
          home: const Scaffold(body: Text('home')),
        ),
      );
      navigator.currentState!
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const UnsavedChangesGuard(
                hasChanges: true,
                child: Scaffold(body: Text('form')),
              ),
            ),
          )
          .ignore();
      await tester.pumpAndSettle();

      await navigator.currentState!.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('form'), findsOneWidget);

      await navigator.currentState!.maybePop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(find.text('form'), findsNothing);
    });
  });

  group('semantics', () {
    testWidgets('AmountText speaks the direction', (tester) async {
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: Column(
              children: [
                AmountText('₹250.00', sign: AmountSign.positive),
                AmountText('₹90.00', sign: AmountSign.negative),
              ],
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Plus ₹250.00'), findsOneWidget);
      expect(find.bySemanticsLabel('Minus ₹90.00'), findsOneWidget);
      expect(find.text('+₹250.00'), findsOneWidget);
      final text = tester.widget<Text>(find.text('−₹90.00'));
      expect(text.style!.color, AppPalette.light.negativeAmount);
    });

    testWidgets('StatusBadge and AppIconButton are labelled', (tester) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Row(
              children: [
                const StatusBadge(StatusBadgeKind.pending),
                AppIconButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Delete expense',
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Pending'), findsOneWidget);
      expect(find.byTooltip('Delete expense'), findsOneWidget);
      expect(tester.getSize(find.byType(IconButton)), const Size(48, 48));
    });
  });

  group('reduced motion', () {
    testWidgets('context.reduceMotion follows the platform flags', (
      tester,
    ) async {
      late bool reduced;
      Widget probe(MediaQueryData data) => MediaQuery(
        data: data,
        child: Builder(
          builder: (context) {
            reduced = context.reduceMotion;
            return const SizedBox();
          },
        ),
      );
      await tester.pumpWidget(probe(const MediaQueryData()));
      expect(reduced, isFalse);
      await tester.pumpWidget(
        probe(const MediaQueryData(disableAnimations: true)),
      );
      expect(reduced, isTrue);
      await tester.pumpWidget(
        probe(const MediaQueryData(accessibleNavigation: true)),
      );
      expect(reduced, isTrue);
    });

    testWidgets('skeletons and MotionSafeAnimate settle when reduced', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Column(
                children: [
                  const SizedBox(height: 120, child: SkeletonList()),
                  MotionSafeAnimate(
                    effects: const [FadeEffect(), ShimmerEffect()],
                    onPlay: (c) => c.repeat(),
                    child: const Text('hello'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      // Would time out if anything kept animating.
      await tester.pumpAndSettle();
      expect(find.text('hello'), findsOneWidget);
      expect(find.bySemanticsLabel('Loading…'), findsOneWidget);
    });

    testWidgets('MinTapTarget grows small controls to 48dp', (tester) async {
      await tester.pumpWidget(
        const Center(
          child: MinTapTarget(child: SizedBox(width: 16, height: 16)),
        ),
      );
      expect(tester.getSize(find.byType(MinTapTarget)), const Size(48, 48));
    });
  });

  group('gallery', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final (width, scale) in [(400.0, 1.0), (320.0, 2.0)]) {
        testWidgets('renders without overflow at ${width}dp x$scale ($mode)', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            _app(
              mode: mode,
              Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true,
                  ),
                  child: const Scaffold(
                    body: SingleChildScrollView(child: KitGallery()),
                  ),
                ),
              ),
            ),
          );
          // The loading button's spinner never settles; pump a frame.
          await tester.pump();
          expect(tester.takeException(), isNull);
          if (scale == 1.0) {
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
          }
        });
      }
    }
  });
}
