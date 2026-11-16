import 'dart:async';
import 'dart:convert';

import 'package:expense_manager/core/storage/preferences.dart';
import 'package:expense_manager/core/theme/app_theme.dart';
import 'package:expense_manager/data/ai/ai_chat_models.dart';
import 'package:expense_manager/data/repositories/ai_report_repository.dart';
import 'package:expense_manager/features/chat/chat_error_copy.dart';
import 'package:expense_manager/features/chat/screens/chat_screen.dart';
import 'package:expense_manager/features/chat/widgets/chat_empty_view.dart';
import 'package:expense_manager/features/chat/widgets/consent_view.dart';
import 'package:expense_manager/features/chat/widgets/report_sheet.dart';
import 'package:expense_manager/features/chat/widgets/safe_markdown.dart';
import 'package:expense_manager/l10n/l10n.dart';
import 'package:expense_manager/providers/chat_provider.dart';
import 'package:expense_manager/providers/profile_provider.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import 'chat_test_support.dart';

final AppLocalizations l10n = lookupAppLocalizations(const Locale('en'));

class _Env {
  _Env(this.container, this.api, this.backend, this.reports, this.launched);

  final ProviderContainer container;
  final FakeAiChatApi api;
  final TestBackend backend;
  final FakeAiReportRepository reports;
  final List<Uri> launched;
}

Future<_Env> _pump(
  WidgetTester tester, {
  required ThemeData theme,
  bool consent = true,
  Widget? child,
  Map<String, Object> prefs = const {},
}) async {
  tester.view
    ..physicalSize = const Size(1200, 2700)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final backend = TestBackend(signedInAs: 'u1');
  backend.profiles.profiles['u1'] = profileOf(
    'u1',
  ).copyWith(aiConsent: consent);
  final api = FakeAiChatApi();
  final reports = FakeAiReportRepository();
  final launched = <Uri>[];
  final container = await tester.runAsync(
    () => chatContainer(
      backend,
      api,
      prefs: prefs,
      reports: reports,
      launched: launched,
    ),
  );
  addTearDown(container!.dispose);
  container.listen(profileProvider, (_, _) {});
  await tester.runAsync(() => container.read(profileProvider.notifier).loaded);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: theme, home: child ?? const ChatScreen()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 10));
  await tester.pump(const Duration(milliseconds: 10));
  return _Env(container, api, backend, reports, launched);
}

/// The live-region node labelled [label] in the semantics tree the platform
/// receives, or null when it is not attached there.
SemanticsNode? _attachedLiveRegion(WidgetTester tester, String label) {
  SemanticsNode? found;
  bool visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.label == label && data.flagsCollection.isLiveRegion) {
      found = node;
      return false;
    }
    node.visitChildren(visit);
    return found == null;
  }

  for (final view in tester.binding.renderViews) {
    final root = view.owner?.semanticsOwner?.rootSemanticsNode;
    if (root != null) visit(root);
  }
  return found;
}

void main() {
  final themes = {'light': AppTheme.lightTheme, 'dark': AppTheme.darkTheme};

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    group('$name theme', () {
      testWidgets('empty state shows prompts and the disclaimer', (
        tester,
      ) async {
        await _pump(tester, theme: theme);
        expect(find.text(l10n.chatEmptyTitle), findsOneWidget);
        // The empty view carries the disclaimer, so the footer leaves it out.
        expect(find.text(l10n.chatDisclaimer), findsOneWidget);
        for (final prompt in chatPrompts(l10n)) {
          expect(find.text(prompt), findsOneWidget);
        }
        final send = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.send_rounded),
        );
        expect(send.onPressed, isNull, reason: 'disabled while empty');
        expect(find.byTooltip('Send message'), findsOneWidget);
      });

      testWidgets('streams a message and offers Stop', (tester) async {
        final env = await _pump(tester, theme: theme);
        await tester.tap(find.text(chatPrompts(l10n).first));
        await tester.pump();
        expect(env.api.calls, hasLength(1));
        expect(find.byTooltip('Stop response'), findsOneWidget);
        expect(find.text('Thinking…'), findsOneWidget);
        expect(find.bySemanticsLabel(l10n.chatResponding), findsOneWidget);

        env.api.last
          ..emit(const AiMeta(AiProvider.claude))
          ..emit(const AiDelta('You spent **₹1,200** on food.'));
        await tester.pump();
        await tester.pump();
        expect(find.textContaining('₹1,200', findRichText: true), findsWidgets);
        expect(find.text('Answers by Claude'), findsOneWidget);
        expect(find.text('Exevra Assistant · Claude'), findsOneWidget);

        await tester.tap(find.byTooltip('Stop response'));
        await tester.pump();
        expect(env.api.last.aborted, isTrue);
        expect(find.text(l10n.chatStopped), findsOneWidget);
        expect(find.byTooltip('Send message'), findsOneWidget);
        expect(find.byTooltip('Copy message'), findsOneWidget);
        expect(find.byTooltip('Report response'), findsOneWidget);
        // Stopping is announced as such, never as a complete answer.
        expect(
          _attachedLiveRegion(tester, l10n.chatAnnounceStopped),
          isNotNull,
        );
        expect(_attachedLiveRegion(tester, l10n.chatAnnounceComplete), isNull);
      });

      testWidgets('error card with Retry', (tester) async {
        final env = await _pump(tester, theme: theme);
        await tester.enterText(find.byType(TextField), 'Hello');
        await tester.pump();
        await tester.tap(find.byTooltip('Send message'));
        await tester.pump();
        await env.api.last.fail(AiErrorCode.rateLimited);
        await tester.pump();
        await tester.pump();

        expect(
          find.text("You're sending messages quickly. Try again in a minute."),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(TextButton, 'Retry'));
        await tester.pump();
        expect(env.api.calls, hasLength(2));
        expect(env.api.last.turns.last, const AiTurn.user('Hello'));
      });

      testWidgets('consent screen explains and saves consent', (tester) async {
        final env = await _pump(tester, theme: theme, consent: false);
        expect(find.byType(ChatConsentView), findsOneWidget);
        expect(find.textContaining("Anthropic's Claude"), findsOneWidget);
        expect(find.textContaining("Google's Gemini"), findsOneWidget);
        expect(
          find.textContaining(
            '15 most recent expenses (title, category, amount and date',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining("time zone, language and today's date"),
          findsOneWidget,
        );
        expect(find.text('Not now'), findsOneWidget);

        await tester.ensureVisible(find.text('Read the privacy policy'));
        await tester.tap(find.text('Read the privacy policy'));
        await tester.pump();
        expect(env.launched.single, ChatConsentView.privacyPolicy);
        expect(env.launched.single.path, '/privacy');

        await tester.ensureVisible(find.text('Allow and continue'));
        await tester.tap(find.text('Allow and continue'));
        await tester.pump();
        await tester.pump();
        expect(
          env.backend.profiles.updates.last.$2.fields['ai_consent'],
          isTrue,
        );
        expect(find.byType(ChatConsentView), findsNothing);
        expect(find.text(l10n.chatEmptyTitle), findsOneWidget);
      });

      testWidgets('Not now leaves the assistant off', (tester) async {
        await _pump(tester, theme: theme, consent: false);
        await tester.ensureVisible(find.text('Not now'));
        await tester.tap(find.text('Not now'));
        await tester.pump();
        expect(find.text('The assistant is off'), findsOneWidget);
        await tester.tap(find.text('Turn on the assistant'));
        await tester.pump();
        expect(find.byType(ChatConsentView), findsOneWidget);
      });

      testWidgets('conversation text meets AA contrast', (tester) async {
        final env = await _pump(tester, theme: theme);
        await tester.enterText(find.byType(TextField), 'Hello');
        await tester.pump();
        await tester.tap(find.byTooltip('Send message'));
        await tester.pump();
        await env.api.last.fail(AiErrorCode.unavailable);
        await tester.pump();
        await tester.pump();
        expect(find.text('Hello'), findsOneWidget);
        expect(
          find.text(chatErrorText(l10n, AiErrorCode.unavailable)),
          findsOne,
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });

      testWidgets('consent text and buttons meet AA contrast', (tester) async {
        await _pump(tester, theme: theme, consent: false);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await tester.ensureVisible(find.text('Not now'));
        await tester.pump();
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });

      testWidgets('a conversation meets the tap-target guidelines', (
        tester,
      ) async {
        final env = await _pump(tester, theme: theme);
        await tester.tap(find.text(chatPrompts(l10n).first));
        await tester.pump();
        await env.api.last.finish([
          const AiMeta(AiProvider.claude),
          const AiDelta('An answer'),
          const AiDone(),
        ]);
        await tester.pump();
        await tester.pump();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });
    });
  }

  group('live announcements', () {
    for (final (name, events, expected) in [
      (
        'a failed answer',
        const <AiStreamEvent>[AiStreamError(AiErrorCode.unavailable)],
        l10n.chatAnnounceFailed(chatErrorText(l10n, AiErrorCode.unavailable)),
      ),
      (
        'a declined answer',
        const <AiStreamEvent>[
          AiStreamError(AiErrorCode.declined, message: 'No.'),
        ],
        l10n.chatAnnounceDeclined,
      ),
      (
        'an interrupted answer',
        const <AiStreamEvent>[
          AiDelta('Half'),
          AiInterrupted(reason: 'timeout'),
        ],
        l10n.chatAnnounceInterrupted,
      ),
    ]) {
      testWidgets('$name is not announced as complete', (tester) async {
        final env = await _pump(tester, theme: AppTheme.light());
        await tester.tap(find.text(chatPrompts(l10n).first));
        await tester.pump();
        await env.api.last.finish(events);
        await tester.pump();
        await tester.pump();
        expect(_attachedLiveRegion(tester, expected), isNotNull);
        expect(_attachedLiveRegion(tester, l10n.chatAnnounceComplete), isNull);
      });
    }

    testWidgets('a quota error reads differently from a rate limit', (
      tester,
    ) async {
      final env = await _pump(tester, theme: AppTheme.light());
      await tester.tap(find.text(chatPrompts(l10n).first));
      await tester.pump();
      await env.api.last.fail(AiErrorCode.quotaExceeded);
      await tester.pump();
      await tester.pump();
      expect(find.text(l10n.chatErrorQuota), findsOneWidget);
      expect(find.text(l10n.chatErrorRateLimited), findsNothing);
      expect(l10n.chatErrorQuota, contains('today'));
      expect(l10n.chatErrorRateLimited, contains('quickly'));
    });

    testWidgets('a saved conversation announces nothing on open', (
      tester,
    ) async {
      final saved = jsonEncode([
        ChatMessage(
          id: 'q',
          isUser: true,
          text: 'Question',
          createdAt: DateTime.utc(2026),
        ).toJson(),
        ChatMessage(
          id: 'a',
          isUser: false,
          text: 'Answer',
          createdAt: DateTime.utc(2026),
        ).toJson(),
      ]);
      await _pump(
        tester,
        theme: AppTheme.light(),
        prefs: {UserPrefs.key('u1', ChatNotifier.historyPref): saved},
      );
      await tester.pump();
      expect(_attachedLiveRegion(tester, l10n.chatAnnounceComplete), isNull);
    });
  });

  group('large text on a small screen', () {
    void smallScreen(WidgetTester tester, {double keyboard = 0}) {
      tester.view
        ..physicalSize = const Size(960, 1920)
        ..devicePixelRatio = 3
        ..viewInsets = FakeViewPadding(bottom: keyboard * 3);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    testWidgets('the conversation fits with the keyboard open', (tester) async {
      final env = await _pump(tester, theme: AppTheme.lightTheme);
      await tester.tap(find.text(chatPrompts(l10n).first));
      await tester.pump();
      await env.api.last.finish([
        const AiDelta('You spent ₹1,200 on food.'),
        const AiDone(),
      ]);
      await tester.pump();
      smallScreen(tester, keyboard: 280);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsOneWidget);
      final list = find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.vertical,
      );
      expect(tester.getSize(list).height, greaterThan(100));
    });

    // The message field and Send must be fully on screen, not clipped by
    // the footer, on a 320x568 phone at 200% text.
    void expectInputVisible(WidgetTester tester, {double keyboard = 0}) {
      final bottom = 568 - keyboard;
      final appBar = tester.getRect(find.byType(AppBar));
      for (final finder in [
        find.byType(TextField),
        find.byTooltip(l10n.chatSend),
      ]) {
        final rect = tester.getRect(finder);
        expect(
          rect.top,
          greaterThanOrEqualTo(appBar.bottom),
          reason: '$finder',
        );
        expect(rect.bottom, lessThanOrEqualTo(bottom), reason: '$finder');
      }
      // Nothing sits on top of Send: a tap at its centre reaches it.
      final send = find.byTooltip(l10n.chatSend);
      final hits = tester.hitTestOnBinding(tester.getCenter(send));
      final sendBox = tester.renderObject(send);
      expect(hits.path.any((e) => e.target == sendBox), isTrue);
    }

    for (final keyboard in [0.0, 250.0]) {
      testWidgets('the message field stays visible at 320x568 '
          '(keyboard ${keyboard.toInt()})', (tester) async {
        final env = await _pump(tester, theme: AppTheme.light());
        tester.view
          ..physicalSize = const Size(960, 1704)
          ..devicePixelRatio = 3
          ..viewInsets = FakeViewPadding(bottom: keyboard * 3);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text(l10n.chatDisclaimer), findsOneWidget);
        expectInputVisible(tester, keyboard: keyboard);

        await tester.enterText(find.byType(TextField), 'Hello');
        await tester.pump();
        await tester.tap(find.byTooltip(l10n.chatSend));
        await tester.pump();
        expect(env.api.calls, hasLength(1));
        await env.api.last.finish([
          const AiDelta('You spent ₹1,200 on food.'),
          const AiDone(),
        ]);
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        expectInputVisible(tester, keyboard: keyboard);
      });
    }

    testWidgets('Thinking… fits 320dp at 200% text', (tester) async {
      final env = await _pump(tester, theme: AppTheme.dark());
      tester.view
        ..physicalSize = const Size(960, 2400)
        ..devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();
      await tester.tap(find.byTooltip(l10n.chatSend));
      await tester.pump();
      await tester.pump();
      expect(find.text(l10n.chatThinking), findsOneWidget);
      expect(tester.takeException(), isNull);
      await env.api.last.finish([const AiDone()]);
      await tester.pump();
    });

    testWidgets('opening the keyboard keeps the newest message in view', (
      tester,
    ) async {
      final env = await _pump(tester, theme: AppTheme.light());
      await tester.tap(find.text(chatPrompts(l10n).first));
      await tester.pump();
      final long = [for (var i = 0; i < 60; i++) 'Line $i of the answer.'];
      await env.api.last.finish([AiDelta(long.join('\n\n')), const AiDone()]);
      await tester.pump();
      await tester.pump();
      final list = find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.vertical,
      );
      final position = tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          )
          .position;
      expect(position.pixels, position.maxScrollExtent);

      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await tester.pump();
      expect(position.pixels, position.maxScrollExtent);
      expect(find.byTooltip(l10n.chatJumpToLatest), findsNothing);
    });

    testWidgets('the link dialog scrolls', (tester) async {
      const url = 'https://example.com/a-very-long-path/that/keeps/going?x=1';
      await _pump(
        tester,
        theme: AppTheme.lightTheme,
        child: const Scaffold(body: SafeMarkdown(data: 'x')),
      );
      smallScreen(tester);
      await tester.pump();
      final context = tester.element(find.byType(SafeMarkdown));
      unawaited(confirmAndOpenLink(context, url, (_) async => true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Open this link?'), findsNothing);
    });

    testWidgets('the report sheet buttons wrap', (tester) async {
      final env = await _pump(tester, theme: AppTheme.darkTheme);
      await tester.tap(find.text(chatPrompts(l10n).first));
      await tester.pump();
      await env.api.last.finish([const AiDelta('An answer'), const AiDone()]);
      await tester.pump();
      await tester.pump();
      smallScreen(tester);
      await tester.pump();
      final bubble = tester.element(find.byTooltip('Report response'));
      unawaited(
        showReportSheet(bubble, env.container.read(chatProvider).messages.last),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Send report'), findsOneWidget);
    });

    testWidgets('the assistant-off view scrolls', (tester) async {
      await _pump(tester, theme: AppTheme.lightTheme, consent: false);
      smallScreen(tester);
      await tester.pump();
      await tester.ensureVisible(find.text('Not now'));
      await tester.tap(find.text('Not now'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Turn on the assistant'));
      expect(find.text('Turn on the assistant'), findsOneWidget);
    });
  });

  testWidgets('a drag toward older messages survives streamed tokens', (
    tester,
  ) async {
    final env = await _pump(tester, theme: AppTheme.lightTheme);
    await tester.tap(find.text(chatPrompts(l10n).first));
    await tester.pump();
    final long = [for (var i = 0; i < 80; i++) 'Line $i of the answer.'];
    env.api.last.emit(AiDelta(long.join('\n\n')));
    await tester.pump();
    await tester.pump();

    final list = find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.vertical,
    );
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position;
    expect(position.pixels, position.maxScrollExtent);

    final gesture = await tester.startGesture(tester.getCenter(list));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 10));
    await tester.pump();
    final dragged = position.pixels;
    expect(dragged, lessThan(position.maxScrollExtent));
    expect(position.maxScrollExtent - dragged, lessThan(48));

    env.api.last.emit(const AiDelta(' More.'));
    await tester.pump();
    await tester.pump();
    expect(position.pixels, dragged);

    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    expect(position.pixels, closeTo(dragged - 20, 0.5));
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));

    env.api.last.emit(const AiDelta(' Even more.'));
    await tester.pump();
    await tester.pump();
    expect(position.pixels, lessThan(position.maxScrollExtent));
    expect(find.byTooltip('Jump to latest'), findsOneWidget);

    await tester.tap(find.byTooltip('Jump to latest'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(position.pixels, position.maxScrollExtent);
    env.api.last.emit(const AiDelta(' Last.'));
    await tester.pump();
    await tester.pump();
    expect(position.pixels, position.maxScrollExtent);
    await env.api.last.finish([const AiDone()]);
    await tester.pump();
  });

  testWidgets('a restored conversation opens at the newest message', (
    tester,
  ) async {
    final saved = jsonEncode([
      for (var i = 0; i < 30; i++)
        ChatMessage(
          id: 'm-$i',
          isUser: i.isEven,
          text: 'Message $i\n\nwith a second paragraph of text.',
          createdAt: DateTime.utc(2026, 1, 1, 0, i),
        ).toJson(),
    ]);
    await _pump(
      tester,
      theme: AppTheme.lightTheme,
      prefs: {UserPrefs.key('u1', ChatNotifier.historyPref): saved},
    );
    await tester.pump();
    await tester.pump();

    final list = find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.vertical,
    );
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(position.pixels, position.maxScrollExtent);
    expect(find.textContaining('Message 29', findRichText: true), findsWidgets);
    expect(find.byTooltip('Jump to latest'), findsNothing);
  });

  testWidgets('streaming status reaches the platform as a live region', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final env = await _pump(tester, theme: AppTheme.lightTheme);
    await tester.tap(find.text(chatPrompts(l10n).first));
    await tester.pump();
    expect(_attachedLiveRegion(tester, l10n.chatResponding), isNotNull);

    await env.api.last.finish([const AiDelta('An answer'), const AiDone()]);
    await tester.pump();
    await tester.pump();
    expect(_attachedLiveRegion(tester, l10n.chatAnnounceComplete), isNotNull);
    handle.dispose();
  });

  testWidgets('server consent_required shows the consent screen', (
    tester,
  ) async {
    final env = await _pump(tester, theme: AppTheme.lightTheme);
    await tester.tap(find.text(chatPrompts(l10n).last));
    await tester.pump();
    await env.api.last.fail(AiErrorCode.consentRequired);
    await tester.pump();
    await tester.pump();
    expect(find.byType(ChatConsentView), findsOneWidget);
  });

  testWidgets('Clear asks first and cancels the request in flight', (
    tester,
  ) async {
    final env = await _pump(tester, theme: AppTheme.darkTheme);
    await tester.tap(find.text(chatPrompts(l10n).first));
    await tester.pump();
    await tester.tap(find.byTooltip('Clear conversation'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Clear conversation?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(env.api.last.aborted, isTrue);
    expect(env.container.read(chatProvider).messages, isEmpty);
  });

  testWidgets('report a response with a reason', (tester) async {
    final env = await _pump(tester, theme: AppTheme.lightTheme);
    await tester.tap(find.text(chatPrompts(l10n).first));
    await tester.pump();
    await env.api.last.finish([
      const AiMeta(AiProvider.gemini),
      const AiDelta('A wrong answer'),
      const AiDone(),
    ]);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Report response'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AiReportReason.inaccurate.label));
    await tester.enterText(
      find.widgetWithText(TextField, 'Add a note (optional)'),
      ' wrong total ',
    );
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();

    final report = env.reports.reports.single;
    expect(report.userId, 'u1');
    expect(report.reason, AiReportReason.inaccurate);
    expect(report.provider, 'gemini');
    expect(report.messageExcerpt, 'A wrong answer');
    expect(report.note, 'wrong total');
    expect(find.text('Thanks. Your report was sent.'), findsOneWidget);
  });

  test('report excerpts are capped at 2000 characters', () {
    final report = AiReport(
      userId: 'u1',
      reason: AiReportReason.other,
      messageExcerpt: 'x' * 5000,
      note: '   ',
    );
    expect(report.messageExcerpt.length, 2000);
    expect(report.note, isNull);
    expect(report.toRow().containsKey('note'), isFalse);
  });

  group('SafeMarkdown', () {
    Future<_Env> pumpMd(WidgetTester tester, String data) => _pump(
      tester,
      theme: AppTheme.lightTheme,
      child: Scaffold(body: SafeMarkdown(data: data)),
    );

    testWidgets('never renders images, only their alt text', (tester) async {
      await pumpMd(
        tester,
        'Look ![tracking pixel](https://attacker.example/p.png) here',
      );
      expect(find.byType(Image), findsNothing);
      expect(find.text('tracking pixel'), findsOneWidget);
    });

    testWidgets('raw HTML stays text', (tester) async {
      await pumpMd(tester, 'a <img src="https://attacker.example/x"> b');
      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('<img', findRichText: true), findsOneWidget);
    });

    testWidgets('links open only after a confirm dialog showing the URL', (
      tester,
    ) async {
      final env = await pumpMd(tester, 'See [this](https://example.com/a?b=1)');
      TapGestureRecognizer? recognizer;
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        text.textSpan?.visitChildren((span) {
          if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
            recognizer = span.recognizer! as TapGestureRecognizer;
          }
          return recognizer == null;
        });
      }
      for (final text in tester.widgetList<SelectableText>(
        find.byType(SelectableText),
      )) {
        text.textSpan?.visitChildren((span) {
          if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
            recognizer = span.recognizer! as TapGestureRecognizer;
          }
          return recognizer == null;
        });
      }
      expect(recognizer, isNotNull);
      recognizer!.onTap!();
      await tester.pumpAndSettle();

      expect(find.text('Open this link?'), findsOneWidget);
      expect(find.text('https://example.com/a?b=1'), findsOneWidget);
      expect(env.launched, isEmpty);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(env.launched.single.toString(), 'https://example.com/a?b=1');
    });

    testWidgets('non-https links cannot be opened', (tester) async {
      final env = await pumpMd(tester, 'x');
      final context = tester.element(find.byType(SafeMarkdown));
      final launch = env.container.read(externalLinkLauncherProvider);
      final done = confirmAndOpenLink(context, 'http://example.com', launch);
      await tester.pumpAndSettle();
      expect(find.text("This link can't be opened"), findsOneWidget);
      expect(find.text('Open'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await done;
      expect(env.launched, isEmpty);
    });
  });
}
