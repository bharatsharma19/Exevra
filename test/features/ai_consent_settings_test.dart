import 'package:expense_manager/core/platform/secure_window.dart';
import 'package:expense_manager/core/router/app_router.dart';
import 'package:expense_manager/features/chat/screens/ai_consent_screen.dart';
import 'package:expense_manager/features/chat/widgets/consent_view.dart';
import 'package:expense_manager/main.dart';
import 'package:expense_manager/providers/profile_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

Future<void> _frames(WidgetTester tester, [int count = 10]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SecureWindow.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SecureWindow.channel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

  Future<(TestBackend, ProviderContainer)> pumpProfile(
    WidgetTester tester, {
    required bool consent,
  }) async {
    tester.view.physicalSize = const Size(1800, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final backend = TestBackend(signedInAs: 'A');
    backend.profiles.profiles['A'] = profileOf(
      'A',
    ).copyWith(aiConsent: consent);
    final c = (await tester.runAsync(backend.container))!;
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const ExevraApp()),
    );
    await _frames(tester);
    c.read(routerProvider).go('/profile');
    await _frames(tester);
    return (backend, c);
  }

  Future<void> tapSwitch(WidgetTester tester) async {
    final toggle = find.byKey(const Key('profile-ai-consent'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await _frames(tester);
  }

  bool? consentOf(ProviderContainer c) =>
      c.read(userProfileProvider)?.aiConsent;

  testWidgets('turning the assistant on shows the disclosure first', (
    tester,
  ) async {
    final (backend, c) = await pumpProfile(tester, consent: false);

    await tapSwitch(tester);

    expect(find.byType(AiConsentScreen), findsOneWidget);
    expect(find.byType(ChatConsentView), findsOneWidget);
    // Nothing is saved before Allow.
    expect(backend.profiles.updates, isEmpty);
    expect(consentOf(c), isFalse);

    await tester.ensureVisible(find.text('Allow and continue'));
    await tester.tap(find.text('Allow and continue'));
    await _frames(tester);

    expect(find.byType(AiConsentScreen), findsNothing);
    expect(backend.profiles.updates.single.$2.fields['ai_consent'], isTrue);
    expect(consentOf(c), isTrue);
  });

  testWidgets('Not now leaves it off and saves nothing', (tester) async {
    final (backend, c) = await pumpProfile(tester, consent: false);

    await tapSwitch(tester);
    await tester.ensureVisible(find.text('Not now'));
    await tester.tap(find.text('Not now'));
    await _frames(tester);

    expect(find.byType(AiConsentScreen), findsNothing);
    expect(backend.profiles.updates, isEmpty);
    expect(consentOf(c), isFalse);
  });

  testWidgets('turning it off is immediate', (tester) async {
    final (backend, c) = await pumpProfile(tester, consent: true);

    await tapSwitch(tester);

    expect(find.byType(AiConsentScreen), findsNothing);
    expect(backend.profiles.updates.single.$2.fields['ai_consent'], isFalse);
    expect(consentOf(c), isFalse);
  });
}
