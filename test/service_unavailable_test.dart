import 'package:expense_manager/features/startup/service_unavailable_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const problems = ['SUPABASE_URL is missing.'];

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    group('ServiceUnavailableApp (${mode.name})', () {
      testWidgets('shows the friendly copy', (tester) async {
        await tester.pumpWidget(ServiceUnavailableApp(themeMode: mode));

        expect(find.text('Service unavailable'), findsOneWidget);
        expect(
          find.text(
            "Exevra can't connect right now. "
            'Please update the app or try again later.',
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);

        final context = tester.element(find.text('Service unavailable'));
        expect(
          Theme.of(context).brightness,
          mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
        );
      });

      testWidgets('hides technical details when asked', (tester) async {
        await tester.pumpWidget(
          ServiceUnavailableApp(
            themeMode: mode,
            problems: problems,
            showDetails: false,
          ),
        );

        expect(find.text('Debug details'), findsNothing);
        expect(find.textContaining('SUPABASE_URL'), findsNothing);
      });

      testWidgets('lists problems in debug builds', (tester) async {
        await tester.pumpWidget(
          ServiceUnavailableApp(themeMode: mode, problems: problems),
        );

        expect(find.text('Debug details'), findsOneWidget);
        expect(find.text('• SUPABASE_URL is missing.'), findsOneWidget);
      });
    });
  }
}
