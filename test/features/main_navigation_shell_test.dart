import 'package:expense_manager/core/platform/connectivity.dart';
import 'package:expense_manager/core/widgets/app_sheet.dart';
import 'package:expense_manager/features/dashboard/screens/main_navigation_shell.dart';
import 'package:expense_manager/l10n/l10n.dart';
import 'package:expense_manager/providers/group_detail_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The shell's Scaffold already moves the tabs above the keyboard and the
/// navigation bar. The tabs (and sheets opened from them) must not get the
/// keyboard inset or the bottom system padding again, or a form sheet is
/// squeezed into a sliver above the keyboard.
void main() {
  const keyboard = 300.0;
  const systemBottom = 24.0;

  late double tabInset;
  late double tabBottomPadding;

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard * 3);
    tester.view.padding = const FakeViewPadding(bottom: systemBottom * 3);
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/tab',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) =>
              MainNavigationShell(navigationShell: shell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/tab',
                  builder: (context, state) => Builder(
                    builder: (context) {
                      tabInset = MediaQuery.viewInsetsOf(context).bottom;
                      tabBottomPadding = MediaQuery.paddingOf(context).bottom;
                      return Scaffold(
                        body: Center(
                          child: TextButton(
                            onPressed: () => showAppSheet<void>(
                              context: context,
                              builder: (_) => const SizedBox(
                                key: Key('sheet-content'),
                                height: 2000,
                              ),
                            ),
                            child: const Text('Open'),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupRealtimeProvider.overrideWith((ref) {}),
          isOfflineProvider.overrideWithValue(false),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tabs do not see the keyboard inset the shell already took', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(tabInset, 0);
    expect(tabBottomPadding, 0);
  });

  testWidgets('a sheet opened from a tab uses the space above the keyboard', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // The sheet's scroll view fills the sheet down to the keyboard: its
    // bottom edge is the top of the keyboard, not a keyboard height above.
    final scroll = find.ancestor(
      of: find.byKey(const Key('sheet-content')),
      matching: find.byType(SingleChildScrollView),
    );
    final bottom = tester.getBottomLeft(scroll).dy;
    const keyboardTop = 2400 / 3 - keyboard;
    expect(bottom, closeTo(keyboardTop, 1));
  });
}
