import 'package:expense_manager/core/accessibility/focus_ring_overlay.dart';
import 'package:expense_manager/core/theme/app_palette.dart';
import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../design_system/contrast.dart';

final _ring = find.byKey(const ValueKey('focus-ring'));

Widget _app(ThemeData theme) => MaterialApp(
  theme: theme,
  home: FocusRingOverlay(
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Rows'),
        actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.add))],
      ),
      body: ListView(
        children: [
          for (var i = 0; i < 30; i++)
            ListTile(title: Text('Row $i'), onTap: () {}),
        ],
      ),
    ),
  ),
);

/// Scrolls the list without a touch (a drag would leave keyboard mode).
Future<void> _scrollBy(WidgetTester tester, double offset) async {
  final position = tester
      .state<ScrollableState>(find.byType(Scrollable).last)
      .position;
  position.jumpTo(position.pixels + offset);
  await tester.pumpAndSettle();
}

Future<void> _tabUntil(WidgetTester tester, String text) async {
  for (var i = 0; i < 40; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final context = FocusManager.instance.primaryFocus?.context;
    final tile = context?.findAncestorWidgetOfExactType<ListTile>();
    if (tile != null && (tile.title! as Text).data == text) return;
  }
  fail('$text never got focus');
}

void main() {
  for (final (name, theme, p) in [
    ('light', AppTheme.light(), AppPalette.light),
    ('dark', AppTheme.dark(), AppPalette.dark),
  ]) {
    testWidgets('$name: a focused tile gets a 3:1 ring', (tester) async {
      await tester.pumpWidget(_app(theme));
      expect(_ring, findsNothing);

      await _tabUntil(tester, 'Row 0');
      expect(_ring, findsOneWidget);
      final border =
          (tester.widget<DecoratedBox>(_ring).decoration as BoxDecoration)
                  .border!
              as Border;
      expect(border.top.color, p.focusRing);
      expect(border.top.width, 2);
      expect(
        contrastRatio(p.focusRing, theme.scaffoldBackgroundColor),
        greaterThanOrEqualTo(3),
      );
      expect(
        tester.getRect(_ring),
        tester.getRect(find.widgetWithText(ListTile, 'Row 0')),
      );
    });
  }

  testWidgets('the ring follows the focused tile as the list scrolls', (
    tester,
  ) async {
    await tester.pumpWidget(_app(AppTheme.light()));
    await _tabUntil(tester, 'Row 3');
    final before = tester.getRect(_ring);

    await _scrollBy(tester, 40);
    final tile = tester.getRect(find.widgetWithText(ListTile, 'Row 3'));
    expect(tester.getRect(_ring), tile);
    expect(tester.getRect(_ring), isNot(before));
  });

  testWidgets('a tile scrolled under the app bar is clipped to the list', (
    tester,
  ) async {
    await tester.pumpWidget(_app(AppTheme.light()));
    await _tabUntil(tester, 'Row 0');
    await _scrollBy(tester, 30);
    final clip = tester.getRect(
      find.ancestor(of: _ring, matching: find.byType(ClipRect)).first,
    );
    expect(clip.top, tester.getRect(find.byType(ListView)).top);
  });

  testWidgets('buttons keep their own ring and touch shows none', (
    tester,
  ) async {
    await tester.pumpWidget(_app(AppTheme.light()));
    await _tabUntil(tester, 'Row 0');
    expect(_ring, findsOneWidget);

    // Focus on a button: it draws its own ring, the overlay draws none.
    FocusManager.instance.primaryFocus?.unfocus();
    Focus.of(tester.element(find.byIcon(Icons.add))).requestFocus();
    await tester.pumpAndSettle();
    expect(_ring, findsNothing);

    // A touch switches to touch highlight mode, which hides the ring.
    await _tabUntil(tester, 'Row 1');
    expect(_ring, findsOneWidget);
    await tester.tap(find.text('Row 1'));
    await tester.pumpAndSettle();
    expect(_ring, findsNothing);
  });
}
