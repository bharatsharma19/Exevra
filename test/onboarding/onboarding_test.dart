import 'package:expense_manager/core/theme/app_palette.dart';
import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:expense_manager/features/onboarding/onboarding.dart';
import 'package:expense_manager/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(
  Widget home, {
  ThemeMode mode = ThemeMode.light,
  double textScale = 1,
  bool reduceMotion = false,
}) => ProviderScope(
  child: MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: mode,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reduceMotion,
      ),
      child: child!,
    ),
    home: home,
  ),
);

Future<bool?> _flag(String key) async =>
    (await SharedPreferences.getInstance()).getBool(key);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('OnboardingStore', () {
    test('flags start unset and persist under the v1 keys', () async {
      final store = OnboardingStore();
      expect(await store.isCompleted(), isFalse);
      expect(await store.isFirstExpenseNudgeDismissed(), isFalse);
      await store.markCompleted();
      await store.dismissFirstExpenseNudge();
      expect(await store.isCompleted(), isTrue);
      expect(await store.isFirstExpenseNudgeDismissed(), isTrue);
      expect(await _flag('onboarding_completed_v1'), isTrue);
      expect(await _flag('first_expense_nudge_dismissed_v1'), isTrue);
    });

    test('a failed read counts as not done', () async {
      final store = OnboardingStore(
        preferences: () => Future.error(StateError('no prefs')),
      );
      expect(await store.isCompleted(), isFalse);
      expect(await store.isFirstExpenseNudgeDismissed(), isFalse);
    });

    test('the provider reads and marks completion', () async {
      SharedPreferences.setMockInitialValues({'onboarding_completed_v1': true});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(await container.read(onboardingCompletedProvider.future), isTrue);
    });

    test('markCompleted updates state at once and persists', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(await container.read(onboardingCompletedProvider.future), isFalse);
      final done = container
          .read(onboardingCompletedProvider.notifier)
          .markCompleted();
      expect(container.read(onboardingCompletedProvider).value, isTrue);
      await done;
      expect(await _flag('onboarding_completed_v1'), isTrue);
    });

    test('a failed save keeps the session state', () async {
      final container = ProviderContainer(
        overrides: [
          onboardingStoreProvider.overrideWithValue(_FailingWriteStore()),
        ],
      );
      addTearDown(container.dispose);
      expect(await container.read(onboardingCompletedProvider.future), isFalse);
      await container
          .read(onboardingCompletedProvider.notifier)
          .markCompleted();
      expect(container.read(onboardingCompletedProvider).value, isTrue);
    });
  });

  group('OnboardingFlow', () {
    testWidgets('Skip on the first page finishes and persists', (tester) async {
      var finished = 0;
      await tester.pumpWidget(
        _app(OnboardingFlow(onFinished: () => finished++)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Track every expense'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(finished, 1);
      expect(await _flag('onboarding_completed_v1'), isTrue);
    });

    testWidgets('Next walks the pages and Get started finishes', (
      tester,
    ) async {
      var finished = 0;
      await tester.pumpWidget(
        _app(OnboardingFlow(onFinished: () => finished++)),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Page 1 of 3'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Split and settle up'), findsOneWidget);
      expect(find.bySemanticsLabel('Page 2 of 3'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Ask about your spending'), findsOneWidget);
      expect(find.textContaining('optional'), findsOneWidget);
      expect(find.bySemanticsLabel('Page 3 of 3'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
      expect(finished, 0);

      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(finished, 1);
      expect(await _flag('onboarding_completed_v1'), isTrue);
    });

    testWidgets('Skip on the last page also finishes', (tester) async {
      var finished = 0;
      await tester.pumpWidget(
        _app(OnboardingFlow(onFinished: () => finished++)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(finished, 1);
    });

    testWidgets('swiping changes pages and back returns', (tester) async {
      await tester.pumpWidget(_app(OnboardingFlow(onFinished: () {})));
      await tester.pumpAndSettle();
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Split and settle up'), findsOneWidget);

      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handled, isTrue);
      expect(find.text('Track every expense'), findsOneWidget);
    });

    testWidgets('reduced motion jumps between pages', (tester) async {
      await tester.pumpWidget(
        _app(OnboardingFlow(onFinished: () {}), reduceMotion: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      // One frame, no animation: the next page is already in place.
      await tester.pump();
      expect(find.text('Split and settle up'), findsOneWidget);
      final controller = tester
          .widget<PageView>(find.byType(PageView))
          .controller!;
      expect(controller.page, 1.0);
    });

    testWidgets('Skip has a tooltip and buttons are labelled', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(OnboardingFlow(onFinished: () {})));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Skip the introduction'), findsOneWidget);
      expect(find.bySemanticsLabel('Skip the introduction'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      final palette = mode == ThemeMode.dark
          ? AppPalette.dark
          : AppPalette.light;

      testWidgets('renders with the theme ($mode)', (tester) async {
        await tester.pumpWidget(
          _app(OnboardingFlow(onFinished: () {}), mode: mode),
        );
        await tester.pumpAndSettle();
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(scaffold.backgroundColor, palette.background);
        final title = tester.widget<Text>(find.text('Track every expense'));
        expect(title.style!.color, palette.textPrimary);
        final dots = tester
            .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
            .map((c) => (c.decoration! as BoxDecoration).color)
            .toList();
        expect(dots, [palette.accent, palette.outline, palette.outline]);
      });

      testWidgets('fits 320dp at 200% text on every page ($mode)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _app(OnboardingFlow(onFinished: () {}), mode: mode, textScale: 2),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(find.text('Get started'), findsOneWidget);
      });
    }
  });

  group('FirstExpenseNudge', () {
    Widget nudge(VoidCallback onAdd, {ThemeMode mode = ThemeMode.light}) =>
        _app(
          Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [FirstExpenseNudge(onAddExpense: onAdd)],
            ),
          ),
          mode: mode,
        );

    testWidgets('calls back from its action', (tester) async {
      var adds = 0;
      await tester.pumpWidget(nudge(() => adds++));
      await tester.pumpAndSettle();
      expect(find.text('Add your first expense'), findsOneWidget);
      await tester.tap(find.text('Add expense'));
      expect(adds, 1);
    });

    testWidgets('dismiss hides it and persists', (tester) async {
      await tester.pumpWidget(nudge(() {}));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Dismiss tip'));
      await tester.pumpAndSettle();
      expect(find.text('Add your first expense'), findsNothing);
      expect(await _flag('first_expense_nudge_dismissed_v1'), isTrue);
    });

    testWidgets('stays hidden once dismissed', (tester) async {
      SharedPreferences.setMockInitialValues({
        'first_expense_nudge_dismissed_v1': true,
      });
      await tester.pumpWidget(nudge(() {}));
      await tester.pumpAndSettle();
      expect(find.text('Add your first expense'), findsNothing);
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('fits 320dp at 200% text ($mode)', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [FirstExpenseNudge(onAddExpense: () {})],
              ),
            ),
            mode: mode,
            textScale: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Add your first expense'), findsOneWidget);
      });
    }
  });
}

class _FailingWriteStore extends OnboardingStore {
  @override
  Future<bool> isCompleted() async => false;

  @override
  Future<void> markCompleted() => Future.error(StateError('disk full'));
}
