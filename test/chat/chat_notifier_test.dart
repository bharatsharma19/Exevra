import 'dart:convert';

import 'package:expense_manager/core/constants/app_constants.dart';
import 'package:expense_manager/core/storage/preferences.dart';
import 'package:expense_manager/data/ai/ai_chat_models.dart';
import 'package:expense_manager/features/chat/chat_copy.dart';
import 'package:expense_manager/providers/auth_provider.dart';
import 'package:expense_manager/providers/chat_provider.dart';
import 'package:expense_manager/providers/profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';
import 'chat_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestBackend backend;
  late FakeAiChatApi api;
  late ProviderContainer container;

  Future<void> boot({Map<String, Object> prefs = const {}}) async {
    backend = TestBackend(signedInAs: 'A');
    backend.profiles.profiles['A'] = profileOf('A').copyWith(aiConsent: true);
    backend.profiles.profiles['B'] = profileOf('B').copyWith(aiConsent: true);
    api = FakeAiChatApi();
    container = await chatContainer(backend, api, prefs: prefs);
    addTearDown(container.dispose);
    container.listen(chatProvider, (_, _) {});
  }

  ChatState chat() => container.read(chatProvider);
  ChatNotifier notifier() => container.read(chatProvider.notifier);
  ChatMessage last() => chat().messages.last;

  /// Starts a send and waits until the request reached the fake server.
  Future<({Future<void> done})> send(String text) async {
    final future = notifier().sendMessage(text);
    await settle();
    return (done: future);
  }

  setUp(() => boot());

  test('happy path streams text and labels the provider', () async {
    final sending = await send('How much on food?');
    expect(chat().isStreaming, isTrue);
    expect(api.last.turns, [const AiTurn.user('How much on food?')]);
    expect(api.last.request.timeZone, 'Asia/Kolkata');

    api.last.emit(const AiMeta(AiProvider.claude));
    api.last.emit(const AiDelta('You spent '));
    await settle();
    expect(last().text, 'You spent ');
    expect(last().isStreaming, isTrue);

    await api.last.finish([const AiDelta('₹1,200.'), const AiDone()]);
    await sending.done;

    expect(last().text, 'You spent ₹1,200.');
    expect(last().status, ChatMessageStatus.done);
    expect(last().provider, AiProvider.claude);
    expect(chat().provider?.label, 'Claude');
    expect(chat().isStreaming, isFalse);
  });

  test('truncated answers are marked', () async {
    final sending = await send('q');
    await api.last.finish([
      const AiMeta(AiProvider.gemini),
      const AiDelta('long'),
      const AiDone(truncated: true),
    ]);
    await sending.done;
    expect(last().status, ChatMessageStatus.truncated);
    expect(chat().provider?.label, 'Gemini');
  });

  test('sends earlier turns and leaves out failed questions', () async {
    var sending = await send('first');
    await api.last.finish([const AiDelta('one'), const AiDone()]);
    await sending.done;

    sending = await send('second');
    await api.last.fail(AiErrorCode.unavailable);
    await sending.done;

    sending = await send('third');
    expect(api.last.turns, const [
      AiTurn.user('first'),
      AiTurn.assistant('one'),
      AiTurn.user('third'),
    ]);
    await api.last.finish([const AiDone()]);
    await sending.done;
  });

  test('history keeps to the server limits', () {
    final messages = <ChatMessage>[
      for (var i = 0; i < 30; i++) ...[
        ChatMessage(
          id: 'u$i',
          isUser: true,
          text: 'q$i',
          createdAt: DateTime.utc(2026),
        ),
        ChatMessage(
          id: 'a$i',
          isUser: false,
          text: 'x' * 5000,
          createdAt: DateTime.utc(2026),
        ),
      ],
    ];
    final turns = ChatNotifier.historyTurns(messages, 'now');
    expect(turns.length, lessThanOrEqualTo(AiChatRequest.maxTurns));
    expect(turns.last, const AiTurn.user('now'));
    expect(turns.first.role, AiRole.user);
    expect(
      turns.every((t) => t.content.length <= AiChatRequest.maxMessageLength),
      isTrue,
    );
    expect(
      turns.fold<int>(0, (s, t) => s + t.content.length),
      lessThanOrEqualTo(AiChatRequest.maxTotalLength),
    );
    // Newest pairs are kept.
    expect(turns[turns.length - 3].content, 'q29');
  });

  test('Stop aborts the request and keeps the partial text', () async {
    final sending = await send('q');
    api.last.emit(const AiDelta('Partial'));
    await settle();

    notifier().stop();
    await sending.done;
    await settle();

    expect(api.last.aborted, isTrue);
    expect(api.last.cancelled, isTrue);
    expect(last().text, 'Partial');
    expect(last().status, ChatMessageStatus.stopped);
    expect(chat().isStreaming, isFalse);
    // Late events of the cancelled request change nothing.
    api.last.emit(const AiDelta(' late'));
    await settle();
    expect(last().text, 'Partial');
  });

  test('Retry re-sends the last question and replaces the reply', () async {
    var sending = await send('q');
    await api.last.fail(AiErrorCode.unavailable);
    await sending.done;
    expect(last().status, ChatMessageStatus.error);
    expect(last().canRetry, isTrue);

    sending = (done: notifier().retry());
    await settle();
    expect(api.calls, hasLength(2));
    expect(api.last.turns, [const AiTurn.user('q')]);
    expect(chat().messages, hasLength(2));
    expect(last().isStreaming, isTrue);

    await api.last.finish([const AiDelta('Answer'), const AiDone()]);
    await sending.done;
    expect(chat().messages.map((m) => m.text), ['q', 'Answer']);
    expect(last().status, ChatMessageStatus.done);
  });

  test('interrupted keeps the partial text and offers Retry', () async {
    final sending = await send('q');
    await api.last.finish([
      const AiMeta(AiProvider.claude),
      const AiDelta('Half an'),
      const AiInterrupted(reason: 'timeout'),
    ]);
    await sending.done;
    expect(last().text, 'Half an');
    expect(last().status, ChatMessageStatus.interrupted);
    expect(last().canRetry, isTrue);
    expect(ChatCopy.interrupted, 'Response interrupted. Tap Retry.');
  });

  test('declined with discard_partial replaces the partial text', () async {
    var sending = await send('q');
    await api.last.finish([
      const AiMeta(AiProvider.claude),
      const AiDelta('Something I should not'),
      const AiStreamError(
        AiErrorCode.declined,
        message: "I can't help with that.",
        discardPartial: true,
      ),
    ]);
    await sending.done;
    expect(last().text, "I can't help with that.");
    expect(last().status, ChatMessageStatus.declined);
    expect(last().canRetry, isFalse);

    // The decline, never the partial text, is sent back as history.
    sending = await send('next');
    expect(api.last.turns, const [
      AiTurn.user('q'),
      AiTurn.assistant("I can't help with that."),
      AiTurn.user('next'),
    ]);
    await api.last.finish([const AiDone()]);
    await sending.done;
  });

  group('error codes map to friendly copy', () {
    const expected = {
      AiErrorCode.rateLimited:
          "You're sending messages quickly. Try again in a minute.",
      AiErrorCode.quotaExceeded:
          "You've reached today's assistant limit. It resets at midnight UTC.",
      AiErrorCode.unavailable:
          'The assistant is unavailable right now. Please try again shortly.',
      AiErrorCode.offline:
          "You're offline. Check your connection and try again.",
    };
    for (final MapEntry(key: code, value: copy) in expected.entries) {
      test(code.name, () async {
        final sending = await send('q');
        await api.last.fail(code);
        await sending.done;
        expect(last().status, ChatMessageStatus.error);
        expect(last().errorCode, code);
        expect(ChatCopy.error(last().errorCode), copy);
        expect(chat().consentRequired, isFalse);
      });
    }

    test('a stream rate_limited is an outage worded by the server', () async {
      const busy = 'The assistant is busy right now. Please try again soon.';
      final sending = await send('q');
      await api.last.finish([
        const AiStreamError(AiErrorCode.rateLimited, message: busy),
      ]);
      await sending.done;
      expect(last().errorCode, AiErrorCode.unavailable);
      expect(
        ChatCopy.error(last().errorCode, serverMessage: last().serverMessage),
        busy,
      );
    });

    test('a stream rate_limited without copy never blames the user', () async {
      final sending = await send('q');
      await api.last.finish([const AiStreamError(AiErrorCode.rateLimited)]);
      await sending.done;
      expect(
        ChatCopy.error(last().errorCode, serverMessage: last().serverMessage),
        isNot(contains('quickly')),
      );
    });

    test('429 quota_exceeded shows the server copy and keeps it', () async {
      const copy =
          "You've used today's assistant messages. It resets at "
          'midnight UTC.';
      final sending = await send('q');
      await api.last.failWith(
        const AiChatException(
          AiErrorCode.quotaExceeded,
          serverMessage: copy,
          retryAfter: Duration(hours: 3),
        ),
      );
      await sending.done;
      expect(last().errorCode, AiErrorCode.quotaExceeded);
      expect(
        ChatCopy.error(last().errorCode, serverMessage: last().serverMessage),
        copy,
      );
      final restored = ChatMessage.fromJson(last().toJson())!;
      expect(restored.serverMessage, copy);
    });

    test('server copy is not used for local-only codes or when huge', () {
      expect(
        ChatCopy.error(AiErrorCode.invalidRequest, serverMessage: 'bad tz'),
        isNot('bad tz'),
      );
      expect(
        ChatCopy.error(AiErrorCode.unavailable, serverMessage: 'x' * 400),
        ChatCopy.error(AiErrorCode.unavailable),
      );
    });

    test('every code has copy and none is raw', () {
      for (final code in AiErrorCode.values) {
        final copy = ChatCopy.error(code);
        expect(copy, isNotEmpty);
        expect(copy, isNot(contains('Exception')));
      }
    });
  });

  test('consent_required switches to the consent state', () async {
    final sending = await send('q');
    await api.last.fail(AiErrorCode.consentRequired);
    await sending.done;
    expect(chat().consentRequired, isTrue);
    expect(last().errorCode, AiErrorCode.consentRequired);

    notifier().consentGranted();
    expect(chat().consentRequired, isFalse);
    expect(last().canRetry, isTrue);
  });

  test('Clear cancels the request in flight and forgets history', () async {
    final sending = await send('q');
    api.last.emit(const AiDelta('Partial'));
    await settle();

    await notifier().clear();
    await sending.done;

    expect(api.last.aborted, isTrue);
    expect(chat().messages, isEmpty);
    expect(chat().isStreaming, isFalse);
    final prefs = container.read(sharedPreferencesProvider);
    expect(
      prefs.containsKey(UserPrefs.key('A', ChatNotifier.historyPref)),
      isFalse,
    );
    api.last.emit(const AiDelta('late'));
    await settle();
    expect(chat().messages, isEmpty);
  });

  group('request zone and locale', () {
    test('ids the server rejects fall back to the offset zone', () {
      const ist = Duration(hours: 5, minutes: 30);
      expect(ChatNotifier.requestTimeZone('Asia/Kolkata', ist), 'Asia/Kolkata');
      expect(ChatNotifier.requestTimeZone('GMT+05:30', ist), 'Asia/Kolkata');
      expect(
        ChatNotifier.requestTimeZone('GMT-5', -const Duration(hours: 5)),
        'Etc/GMT+5',
      );
      expect(ChatNotifier.requestTimeZone('', Duration.zero), 'UTC');
    });

    test('malformed locales are left out', () {
      expect(ChatNotifier.requestLocale('en-IN'), 'en-IN');
      expect(ChatNotifier.requestLocale('en_IN'), 'en-IN');
      expect(ChatNotifier.requestLocale('zh-Hant-TW'), 'zh-Hant-TW');
      expect(ChatNotifier.requestLocale('es-419'), 'es-419');
      expect(ChatNotifier.requestLocale('en-12'), isNull);
      expect(ChatNotifier.requestLocale('e'), isNull);
      expect(ChatNotifier.requestLocale(null), isNull);
    });

    test('the request carries the checked values', () async {
      final sending = await send('q');
      expect(api.last.request.timeZone, 'Asia/Kolkata');
      expect(api.last.request.locale, isNotNull);
      await api.last.finish([const AiDone()]);
      await sending.done;
    });
  });

  test('turning the assistant off deletes the conversation', () async {
    final sending = await send('q');
    await api.last.finish([const AiDelta('Food: 1200'), const AiDone()]);
    await sending.done;
    final prefs = container.read(sharedPreferencesProvider);
    final key = UserPrefs.key('A', ChatNotifier.historyPref);
    expect(prefs.containsKey(key), isTrue);

    await container.read(profileProvider.future);
    expect(
      await container.read(profileProvider.notifier).setAiConsent(false),
      isNull,
    );
    await settle();

    expect(chat().messages, isEmpty);
    expect(prefs.containsKey(key), isFalse);
  });

  test('history is not restored while the assistant is off', () async {
    final key = UserPrefs.key('A', ChatNotifier.historyPref);
    final saved = jsonEncode([
      ChatMessage(
        id: 'u-1',
        isUser: true,
        text: 'q',
        createdAt: DateTime.utc(2026),
      ).toJson(),
    ]);
    backend.profiles.profiles['A'] = profileOf('A').copyWith(aiConsent: false);
    container.dispose();
    container = await chatContainer(backend, api, prefs: {key: saved});
    addTearDown(container.dispose);
    await container.read(profileProvider.future);
    container.listen(chatProvider, (_, _) {});
    await settle();
    expect(chat().messages, isEmpty);
    expect(container.read(sharedPreferencesProvider).containsKey(key), isFalse);
  });

  test('ignores blank, oversize and concurrent sends', () async {
    await notifier().sendMessage('   ');
    await notifier().sendMessage(
      'x' * (AiChatRequest.maxUserMessageLength + 1),
    );
    expect(api.calls, isEmpty);

    final sending = await send('q');
    await notifier().sendMessage('again');
    expect(api.calls, hasLength(1));
    await api.last.finish([const AiDone()]);
    await sending.done;
  });

  test('every quick prompt is sent to the server unchanged', () async {
    for (final prompt in AppConstants.aiQuickPrompts) {
      final sending = await send(prompt);
      expect(api.last.turns.last, AiTurn.user(prompt));
      await api.last.finish([const AiDelta('ok'), const AiDone()]);
      await sending.done;
    }
    expect(api.calls, hasLength(AppConstants.aiQuickPrompts.length));
  });

  group('persistence', () {
    test('history is saved per user and restored', () async {
      final sending = await send('q');
      await api.last.finish([
        const AiMeta(AiProvider.claude),
        const AiDelta('a'),
        const AiDone(),
      ]);
      await sending.done;

      final prefs = container.read(sharedPreferencesProvider);
      final key = UserPrefs.key('A', ChatNotifier.historyPref);
      expect(prefs.getString(key), isNotNull);

      // A fresh start on the same device restores it.
      final saved = {key: prefs.getString(key)!};
      container.dispose();
      final again = await chatContainer(backend, FakeAiChatApi(), prefs: saved);
      addTearDown(again.dispose);
      final restored = again.read(chatProvider).messages;
      expect(restored.map((m) => m.text), ['q', 'a']);
      expect(restored.last.provider, AiProvider.claude);
    });

    test('an answer saved while streaming comes back interrupted', () async {
      await send('q');
      api.last.emit(const AiDelta('part'));
      await settle();
      final prefs = await SharedPreferences.getInstance();
      final key = UserPrefs.key('A', ChatNotifier.historyPref);
      final raw = prefs.getString(key)!;
      final again = await chatContainer(
        backend,
        FakeAiChatApi(),
        prefs: {key: raw},
      );
      addTearDown(again.dispose);
      expect(
        again.read(chatProvider).messages.last.status,
        ChatMessageStatus.interrupted,
      );
    });

    test('at most 50 messages are kept, starting with a question', () async {
      final key = UserPrefs.key('A', ChatNotifier.historyPref);
      final many = [
        for (var i = 0; i < 61; i++)
          ChatMessage(
            id: 'm$i',
            isUser: i.isEven,
            text: 't$i',
            createdAt: DateTime.utc(2026),
          ).toJson(),
      ];
      container.dispose();
      container = await chatContainer(
        backend,
        api,
        prefs: {key: jsonEncode(many)},
      );
      final restored = container.read(chatProvider).messages;
      expect(
        restored.length,
        lessThanOrEqualTo(ChatNotifier.maxStoredMessages),
      );
      expect(restored.first.isUser, isTrue);
      expect(restored.last.text, 't60');
    });

    test('sign-out clears it and another user never sees it', () async {
      final sending = await send('secret A');
      await api.last.finish([const AiDelta('answer A'), const AiDone()]);
      await sending.done;
      final prefs = container.read(sharedPreferencesProvider);
      expect(
        prefs.containsKey(UserPrefs.key('A', ChatNotifier.historyPref)),
        isTrue,
      );

      await container.read(authNotifierProvider.notifier).signOut();
      await settle();
      expect(chat().messages, isEmpty);
      expect(prefs.getKeys().where((k) => k.startsWith('u.A.')), isEmpty);

      backend.auth.signIn('B');
      await settle();
      expect(container.read(currentUserIdProvider), 'B');
      expect(chat().messages, isEmpty);
    });

    test('history of one uid is not visible to another', () async {
      final keyA = UserPrefs.key('A', ChatNotifier.historyPref);
      final saved = jsonEncode([
        ChatMessage(
          id: 'm1',
          isUser: true,
          text: 'only A',
          createdAt: DateTime.utc(2026),
        ).toJson(),
      ]);
      container.dispose();
      backend = TestBackend(signedInAs: 'B');
      container = await chatContainer(backend, api, prefs: {keyA: saved});
      expect(container.read(chatProvider).messages, isEmpty);
    });

    test('a reply that arrives after a user switch is dropped', () async {
      final sending = await send('q');
      await container.read(authNotifierProvider.notifier).signOut();
      await settle();
      expect(api.last.aborted, isTrue);
      backend.auth.signIn('B');
      await settle();
      api.last.emit(const AiDelta('for A'));
      await settle();
      await sending.done;
      expect(chat().messages, isEmpty);
      final prefs = container.read(sharedPreferencesProvider);
      expect(
        prefs.containsKey(UserPrefs.key('B', ChatNotifier.historyPref)),
        isFalse,
      );
    });
  });
}
