import 'dart:convert';
import 'dart:io';

import 'package:expense_manager/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards against secrets, server-only integrations and demo shortcuts
/// creeping back into the client. Reads the sources from disk.
void main() {
  final libFiles =
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final sources = {
    for (final file in libFiles)
      file.path.replaceAll(r'\', '/'): file.readAsStringSync(),
  };
  final pubspec = File('pubspec.yaml').readAsStringSync();

  List<String> filesContaining(Pattern pattern) => [
    for (final entry in sources.entries)
      if (entry.value.contains(pattern)) entry.key,
  ];

  test('lib/ sources were found', () {
    expect(sources, isNotEmpty);
  });

  group('pubspec.yaml', () {
    test('does not depend on flutter_dotenv or mailer', () {
      expect(pubspec, isNot(contains('flutter_dotenv')));
      expect(pubspec, isNot(contains('mailer')));
    });

    test('does not bundle a .env asset', () {
      expect(
        RegExp(r'^\s*-\s*\.env\b', multiLine: true).hasMatch(pubspec),
        isFalse,
      );
    });
  });

  group('lib/', () {
    for (final marker in [
      'flutter_dotenv',
      'mailer',
      'sk-ant',
      'AIza',
      'deepseek',
      'openai',
      'api.anthropic.com',
      'generativelanguage.googleapis.com',
      'x-goog-api-key',
      'x-api-key',
      'smtp',
    ]) {
      test('contains no "$marker" (case-insensitive)', () {
        expect(
          filesContaining(RegExp(RegExp.escape(marker), caseSensitive: false)),
          isEmpty,
        );
      });
    }

    test('names AI providers only as display labels in the assistant', () {
      // The consent text and the answer label name the providers; no other
      // file may refer to them (provider calls live in the Edge Function).
      for (final marker in ['anthropic', 'gemini', 'claude-']) {
        expect(
          filesContaining(RegExp(marker, caseSensitive: false)),
          everyElement(
            isIn([
              'lib/data/ai/ai_chat_models.dart',
              'lib/features/chat/widgets/consent_view.dart',
            ]),
          ),
          reason: marker,
        );
      }
    });

    test('has no private key material', () {
      expect(filesContaining('PRIVATE KEY'), isEmpty);
      expect(filesContaining('service_role'), isEmpty);
    });

    test('has no legacy demo shortcuts', () {
      expect(filesContaining('isDemoMode'), isEmpty);
      expect(filesContaining('_enterDemoSession'), isEmpty);
      // The validator lists it as a placeholder marker to reject.
      expect(filesContaining('xyzcompany'), [
        'lib/core/config/app_config.dart',
      ]);
    });

    test('reads build configuration only in app_config', () {
      expect(filesContaining('String.fromEnvironment'), [
        'lib/core/config/app_config.dart',
      ]);
      expect(filesContaining('bool.fromEnvironment'), isEmpty);
    });

    test('has no demo mode or fake data fallback', () {
      for (final marker in [
        'kDemoMode',
        'DemoBackend',
        'DemoSession',
        'demo-user-id',
        'grp-demo',
        'SupabaseService',
        '_localExpenses',
      ]) {
        expect(filesContaining(marker), isEmpty, reason: marker);
      }
    });

    test('does not write directly to the console', () {
      final offenders = [
        for (final entry in sources.entries)
          if (entry.key != 'lib/core/logging/app_logger.dart' &&
              RegExp(r'\b(debugPrint|print)\(').hasMatch(entry.value))
            entry.key,
      ];
      expect(offenders, isEmpty);
    });
  });

  group('config/', () {
    test('the example config only holds placeholders', () {
      final example =
          jsonDecode(File('config/dev.example.json').readAsStringSync())
              as Map<String, Object?>;
      final problems = AppConfig.validate(
        supabaseUrl: example['SUPABASE_URL']! as String,
        supabaseAnonKey: example['SUPABASE_ANON_KEY']! as String,
        appLinkHost: example['APP_LINK_HOST']! as String,
        isRelease: true,
      );
      expect(problems, hasLength(2));
    });

    test('the legacy .env example is gone', () {
      expect(File('.env.example').existsSync(), isFalse);
    });
  });
}
