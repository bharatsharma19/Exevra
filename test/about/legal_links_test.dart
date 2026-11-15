import 'package:expense_manager/core/config/app_config.dart';
import 'package:expense_manager/core/config/legal_links.dart';
import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:expense_manager/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LegalLinks', () {
    const links = LegalLinks('exevra.app');

    test('pages are https on the app link host', () {
      expect(links.privacyPolicy.toString(), 'https://exevra.app/privacy');
      expect(links.terms.toString(), 'https://exevra.app/terms');
      expect(
        links.deleteAccount.toString(),
        'https://exevra.app/delete-account',
      );
      expect(links.support.toString(), 'https://exevra.app/support');
    });

    test('the support email is derived from the host', () {
      expect(links.supportEmail, 'support@exevra.app');
      expect(
        const LegalLinks('staging.exevra.app').supportEmail,
        'support@staging.exevra.app',
      );
    });

    test('follows the configured host', () {
      const config = AppConfig(
        supabaseUrl: 'https://abc.supabase.co',
        supabaseAnonKey: 'key',
        appLinkHost: ' other.example.org ',
      );
      final fromConfig = LegalLinks.fromConfig(config);
      expect(fromConfig.host, 'other.example.org');
      expect(fromConfig.terms.host, 'other.example.org');
      expect(LegalLinks.current.host, AppConfig.environment.appLinkHost.trim());
      expect(fromConfig, const LegalLinks('other.example.org'));
      expect(
        fromConfig.hashCode,
        const LegalLinks('other.example.org').hashCode,
      );
    });

    test('mailto link encodes the subject and body', () {
      final uri = links.supportEmailUri(
        subject: 'Exevra support',
        body: 'App version: 1.0.0 (1)\n',
      );
      expect(uri.scheme, 'mailto');
      expect(uri.path, 'support@exevra.app');
      expect(
        uri.query,
        'subject=Exevra%20support&body=App%20version%3A%201.0.0%20(1)%0A',
      );
      expect(uri.toString(), isNot(contains('+')));
      expect(uri.queryParameters['subject'], 'Exevra support');
      expect(links.supportEmailUri().toString(), 'mailto:support@exevra.app');
      expect(
        links.supportEmailUri(subject: 'Hi').toString(),
        'mailto:support@exevra.app?subject=Hi',
      );
    });
  });

  group('openExternal', () {
    Future<BuildContext> pumpHost(WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return context;
    }

    final uri = Uri.parse('https://exevra.app/privacy');

    testWidgets('returns true and shows nothing when the link opens', (
      tester,
    ) async {
      final context = await pumpHost(tester);
      Uri? opened;
      final result = await openExternal(
        context,
        uri,
        launcher: (u) async {
          opened = u;
          return true;
        },
      );
      await tester.pump();
      expect(result, isTrue);
      expect(opened, uri);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('shows a friendly error when nothing can open it', (
      tester,
    ) async {
      final context = await pumpHost(tester);
      final result = await openExternal(
        context,
        uri,
        launcher: (_) async => false,
      );
      await tester.pump();
      expect(result, isFalse);
      expect(
        find.text("Couldn't open the link. Please try again later."),
        findsOneWidget,
      );
    });

    testWidgets('a launcher error becomes the custom message', (tester) async {
      final context = await pumpHost(tester);
      final result = await openExternal(
        context,
        uri,
        failureMessage: 'No email app',
        launcher: (_) => throw Exception('no activity'),
      );
      await tester.pump();
      expect(result, isFalse);
      expect(find.text('No email app'), findsOneWidget);
    });
  });
}
