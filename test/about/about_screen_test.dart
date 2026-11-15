import 'package:expense_manager/core/config/legal_links.dart';
import 'package:expense_manager/core/theme/app_palette.dart';
import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:expense_manager/core/widgets/widgets.dart';
import 'package:expense_manager/features/about/about_screen.dart';
import 'package:expense_manager/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _links = LegalLinks('exevra.app');

Widget _app(
  Widget home, {
  ThemeMode mode = ThemeMode.light,
  double textScale = 1,
}) => MaterialApp(
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: mode,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: home,
);

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Exevra',
      packageName: 'com.exevra.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final palette = mode == ThemeMode.dark ? AppPalette.dark : AppPalette.light;

    testWidgets('shows the brand, version, credit and rows ($mode)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          AboutScreen(links: _links, onDeleteAccount: () {}),
          mode: mode,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('About'), findsOneWidget);
      expect(find.byType(BrandMark), findsOneWidget);
      expect(find.text('Exevra'), findsOneWidget);
      expect(find.text('Expense & Split Tracker'), findsOneWidget);
      expect(find.text('Version 1.0.0 (1)'), findsOneWidget);
      expect(
        find.text('Designed & developed by Bharat Sharma'),
        findsOneWidget,
      );
      for (final row in [
        'Privacy Policy',
        'Terms of Use',
        'Help & Support',
        'Open-source licences',
        'Account deletion info',
      ]) {
        expect(find.text(row), findsOneWidget, reason: row);
      }
      expect(find.text('support@exevra.app'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Delete account'), 100);
      expect(find.text('Delete account'), findsOneWidget);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).scaffoldBackgroundColor,
        palette.background,
      );
      expect(scaffold.backgroundColor, isNull);

      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Delete account'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.style!.backgroundColor!.resolve({}), palette.danger);
    });
  }

  testWidgets('legal rows open their pages', (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      _app(
        AboutScreen(
          links: _links,
          launcher: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Privacy Policy'));
    await tester.tap(find.text('Terms of Use'));
    await tester.scrollUntilVisible(find.text('Account deletion info'), 100);
    await tester.tap(find.text('Account deletion info'));
    await tester.pump();
    expect(opened, [
      Uri.parse('https://exevra.app/privacy'),
      Uri.parse('https://exevra.app/terms'),
      Uri.parse('https://exevra.app/delete-account'),
    ]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Help & Support emails support with the app version', (
    tester,
  ) async {
    Uri? opened;
    await tester.pumpWidget(
      _app(
        AboutScreen(
          links: _links,
          launcher: (uri) async {
            opened = uri;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Help & Support'));
    await tester.pump();
    expect(opened!.scheme, 'mailto');
    expect(opened!.path, 'support@exevra.app');
    expect(opened!.queryParameters['subject'], 'Exevra support');
    expect(opened!.queryParameters['body'], 'App version: 1.0.0 (1)');
  });

  testWidgets('a link that cannot open shows a friendly error', (tester) async {
    await tester.pumpWidget(
      _app(AboutScreen(links: _links, launcher: (_) async => false)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Help & Support'));
    await tester.pump();
    expect(
      find.text(
        "Couldn't open an email app. Write to us at support@exevra.app.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Privacy Policy'));
    await tester.pump();
    expect(
      find.text("Couldn't open the link. Please try again later."),
      findsOneWidget,
    );
  });

  testWidgets('Delete account is hidden without a callback', (tester) async {
    await tester.pumpWidget(_app(const AboutScreen(links: _links)));
    await tester.pumpAndSettle();
    expect(find.text('Delete account'), findsNothing);
    // The web page about deleting an account is always available.
    expect(find.text('Account deletion info'), findsOneWidget);
  });

  testWidgets('Delete account calls back', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _app(AboutScreen(links: _links, onDeleteAccount: () => calls++)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Delete account'), 100);
    await tester.tap(find.text('Delete account'));
    expect(calls, 1);
  });

  testWidgets('licences open the licence page with the legalese', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const AboutScreen(links: _links)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open-source licences'));
    // The licence page loads asynchronously and shows a spinner, so it never
    // settles; pump a few frames instead.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(LicensePage), findsOneWidget);
    final page = tester.widget<LicensePage>(find.byType(LicensePage));
    expect(page.applicationName, 'Exevra');
    expect(page.applicationVersion, 'Version 1.0.0 (1)');
    expect(page.applicationLegalese, '© 2026 Bharat Sharma');
  });

  testWidgets('rows are labelled and at least 48dp tall', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(AboutScreen(links: _links, onDeleteAccount: () {})),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        RegExp('Privacy Policy.*Opens in your browser', dotAll: true),
      ),
      findsOneWidget,
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('fits 320dp at 200% text ($mode)', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          AboutScreen(links: _links, onDeleteAccount: () {}),
          mode: mode,
          textScale: 2,
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Delete account'), 200);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
