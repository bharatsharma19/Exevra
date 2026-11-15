import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';
import '../core/platform/device_time_zone.dart';
import '../core/storage/preferences.dart';
import '../data/ai/ai_chat_client.dart';
import '../data/ai/ai_chat_models.dart';
import '../features/chat/chat_copy.dart';
import '../features/chat/models/chat_message.dart';
import 'auth_provider.dart';
import 'profile_provider.dart';
import 'session_guard.dart';

export '../features/chat/models/chat_message.dart';

/// The conversation of the signed-in user.
class ChatState {
  const ChatState({this.messages = const [], this.consentRequired = false});

  final List<ChatMessage> messages;

  /// The server answered `consent_required`: show the consent screen even
  /// if the local profile says otherwise.
  final bool consentRequired;

  /// An answer is streaming.
  bool get isStreaming => messages.isNotEmpty && messages.last.isStreaming;

  /// The model of the latest answer that named one.
  AiProvider? get provider {
    for (final m in messages.reversed) {
      if (!m.isUser && m.provider != null) return m.provider;
    }
    return null;
  }

  ChatState copyWith({List<ChatMessage>? messages, bool? consentRequired}) =>
      ChatState(
        messages: messages ?? this.messages,
        consentRequired: consentRequired ?? this.consentRequired,
      );
}

class _InFlight {
  _InFlight(this.messageId);

  final String messageId;
  final Completer<void> abort = Completer<void>();
  final Completer<void> done = Completer<void>();
  StreamSubscription<AiStreamEvent>? subscription;

  void complete() {
    if (!done.isCompleted) done.complete();
  }

  void cancel() {
    if (!abort.isCompleted) abort.complete();
    unawaited(subscription?.cancel());
    complete();
  }
}

/// The assistant conversation of the current user: multi-turn history,
/// streaming answers, Stop, Retry and Clear. History is kept per user under
/// a [UserPrefs] key, so sign-out removes it.
class ChatNotifier extends Notifier<ChatState> {
  static const String historyPref = 'chat_history';
  static const int maxStoredMessages = 50;

  /// Question/answer pairs sent before the new question (20 turns at most).
  static const int maxHistoryPairs = 9;

  String? _uid;
  _InFlight? _active;
  int _seq = 0;

  @override
  ChatState build() {
    final uid = ref.watch(currentUserIdProvider);
    _uid = uid;
    ref.onDispose(() {
      _active?.cancel();
      _active = null;
    });
    // Turning the assistant off deletes the conversation from the device.
    ref.listen(userProfileProvider.select((p) => p?.aiConsent), (prev, next) {
      if (next == false && prev != false) unawaited(clear());
    });
    if (uid == null) return const ChatState();
    if (ref.read(userProfileProvider)?.aiConsent == false) {
      unawaited(_removeHistory(uid));
      return const ChatState();
    }
    return ChatState(messages: _load(uid));
  }

  /// Whether the signed-in user allowed the assistant (the loaded profile
  /// says so). Nothing is sent otherwise, whatever the screen shows.
  bool get _consented => ref.read(userProfileProvider)?.aiConsent ?? false;

  /// Sends [text] as a new question. Ignored while an answer is streaming,
  /// when blank or longer than the server allows, and without AI consent.
  Future<void> sendMessage(String text) async {
    final question = text.trim();
    if (question.isEmpty ||
        question.length > AiChatRequest.maxUserMessageLength ||
        state.isStreaming ||
        _uid == null) {
      return;
    }
    if (!_consented) {
      AppLogger.debug('Assistant message not sent: no AI consent');
      return;
    }
    final prior = state.messages;
    final now = DateTime.now().toUtc();
    final user = ChatMessage(
      id: _newId('u'),
      isUser: true,
      text: question,
      createdAt: now,
    );
    final answer = ChatMessage(
      id: _newId('a'),
      isUser: false,
      text: '',
      createdAt: now,
      status: ChatMessageStatus.streaming,
    );
    state = state.copyWith(messages: [...prior, user, answer]);
    _persist();
    await _start(answer.id, historyTurns(prior, question));
  }

  /// Sends the last question again, replacing the failed or partial answer.
  Future<void> retry() async {
    final messages = state.messages;
    if (messages.length < 2 || state.isStreaming || !_consented) return;
    final last = messages.last;
    final question = messages[messages.length - 2];
    if (!last.canRetry || !question.isUser) return;
    final replacement = ChatMessage(
      id: _newId('a'),
      isUser: false,
      text: '',
      createdAt: DateTime.now().toUtc(),
      status: ChatMessageStatus.streaming,
    );
    final prior = messages.sublist(0, messages.length - 2);
    state = state.copyWith(messages: [...prior, question, replacement]);
    _persist();
    await _start(replacement.id, historyTurns(prior, question.text));
  }

  /// Cancels the streaming answer and keeps the text received so far.
  void stop() {
    final active = _active;
    if (active == null) return;
    active.cancel();
    _active = null;
    _update(
      active.messageId,
      (m) => m.copyWith(status: ChatMessageStatus.stopped),
    );
    _persist();
  }

  /// Cancels any request in flight and deletes the conversation.
  Future<void> clear() async {
    _active?.cancel();
    _active = null;
    state = const ChatState();
    final uid = _uid;
    if (uid == null) return;
    await _removeHistory(uid);
  }

  Future<void> _removeHistory(String uid) async {
    try {
      await ref
          .read(sharedPreferencesProvider)
          .remove(UserPrefs.key(uid, historyPref));
    } on Object catch (e) {
      AppLogger.warn('Could not clear the chat history', e.runtimeType);
    }
  }

  static final RegExp _zoneChars = RegExp(r'^[A-Za-z0-9_+\-/]{1,64}$');
  static final RegExp _gmtOffset = RegExp(r'^GMT[+-]');

  // language[-script][-region](-variant)*, as Intl canonicalises it.
  static final RegExp _localeTag = RegExp(
    r'^[A-Za-z]{2,3}(-[A-Za-z]{4})?(-([A-Za-z]{2}|[0-9]{3}))?'
    r'(-([A-Za-z0-9]{5,8}|[0-9][A-Za-z0-9]{3}))*$',
  );

  /// [zone] when the server can accept it, else an IANA zone with the
  /// device's [offset] (Android reports custom zones as `GMT+05:30`).
  static String requestTimeZone(String zone, Duration offset) =>
      _zoneChars.hasMatch(zone) && !_gmtOffset.hasMatch(zone)
      ? zone
      : DeviceTimeZone.fallbackForOffset(offset);

  /// [locale] as a well-formed BCP 47 tag, or null to leave it out (the
  /// server rejects tags Intl cannot canonicalise).
  static String? requestLocale(String? locale) {
    if (locale == null) return null;
    final tag = locale.trim().replaceAll('_', '-');
    return tag.length <= 35 && _localeTag.hasMatch(tag) ? tag : null;
  }

  /// The user allowed the assistant (consent saved on the server).
  void consentGranted() {
    if (state.consentRequired) state = state.copyWith(consentRequired: false);
  }

  /// The turns sent for [question]: the newest complete question/answer
  /// pairs of [prior] that fit the server's limits, then [question].
  static List<AiTurn> historyTurns(List<ChatMessage> prior, String question) {
    final pairs = <(AiTurn, AiTurn)>[];
    for (var i = 0; i + 1 < prior.length; i++) {
      final q = prior[i];
      final a = prior[i + 1];
      if (!q.isUser || a.isUser) continue;
      i++;
      if (q.text.trim().isEmpty || !a.hasUsableText) continue;
      pairs.add((
        AiTurn.user(_clip(q.text, AiChatRequest.maxMessageLength)),
        AiTurn.assistant(_clip(a.text, AiChatRequest.maxMessageLength)),
      ));
    }
    var kept = pairs.length > maxHistoryPairs
        ? pairs.sublist(pairs.length - maxHistoryPairs)
        : pairs;
    int total() =>
        question.length +
        kept.fold<int>(
          0,
          (sum, p) => sum + p.$1.content.length + p.$2.content.length,
        );
    while (kept.isNotEmpty && total() > AiChatRequest.maxTotalLength) {
      kept = kept.sublist(1);
    }
    return [
      for (final (q, a) in kept) ...[q, a],
      AiTurn.user(question),
    ];
  }

  static String _clip(String text, int max) {
    if (text.length <= max) return text;
    var end = max;
    final last = text.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
    return text.substring(0, end);
  }

  Future<void> _start(String messageId, List<AiTurn> turns) async {
    _active?.cancel();
    final flight = _InFlight(messageId);
    _active = flight;
    // The reply belongs to the session that asked: if the user signs out
    // (or another user signs in) while it streams, it is dropped.
    final session = SessionGuard.start(() => ref);
    bool current() =>
        ref.mounted && identical(_active, flight) && session.isCurrent;

    String zone;
    try {
      zone = await ref.read(deviceTimeZoneProvider.future);
    } on Object {
      zone = DeviceTimeZone.fallbackForOffset(DateTime.now().timeZoneOffset);
    }
    if (!current()) return flight.done.future;
    final locale =
        ref.read(userProfileProvider)?.locale ?? ref.read(deviceLocaleProvider);
    final request = AiChatRequest(
      messages: turns,
      timeZone: requestTimeZone(zone, DateTime.now().timeZoneOffset),
      locale: requestLocale(locale),
    );

    void finish() {
      if (identical(_active, flight)) _active = null;
      _persist();
      flight.complete();
    }

    final AiChatApi api;
    try {
      api = ref.read(aiChatApiProvider);
    } on Object catch (e, s) {
      AppLogger.error('Assistant client unavailable', e, s);
      _fail(messageId, AiErrorCode.unavailable);
      finish();
      return flight.done.future;
    }
    flight.subscription = api
        .stream(request, abortTrigger: flight.abort.future)
        .listen(
          (event) {
            if (!current()) return;
            _onEvent(messageId, event, finish);
          },
          onError: (Object error, StackTrace stack) {
            if (!current()) return;
            final code = error is AiChatException
                ? error.code
                : AiErrorCode.unknown;
            if (error is! AiChatException) {
              AppLogger.error('Assistant stream failed', error, stack);
            }
            if (code == AiErrorCode.aborted) return;
            _fail(
              messageId,
              code,
              error is AiChatException ? error.serverMessage : null,
            );
            finish();
          },
          onDone: () {
            if (current()) {
              _update(messageId, (m) {
                if (!m.isStreaming) return m;
                return m.text.isEmpty
                    ? m.copyWith(
                        status: ChatMessageStatus.error,
                        errorCode: AiErrorCode.network,
                      )
                    : m.copyWith(status: ChatMessageStatus.interrupted);
              });
              finish();
            }
            flight.complete();
          },
        );
    return flight.done.future;
  }

  void _onEvent(String id, AiStreamEvent event, void Function() finish) {
    switch (event) {
      case AiMeta(:final provider):
        _update(id, (m) => m.copyWith(provider: provider));
      case AiDelta(:final text):
        _update(id, (m) => m.copyWith(text: m.text + text));
      case AiDone(:final truncated):
        _update(
          id,
          (m) => m.copyWith(
            status: truncated
                ? ChatMessageStatus.truncated
                : ChatMessageStatus.done,
          ),
        );
        finish();
      case AiInterrupted():
        _update(
          id,
          (m) => m.copyWith(
            status: m.text.isEmpty
                ? ChatMessageStatus.error
                : ChatMessageStatus.interrupted,
            errorCode: m.text.isEmpty ? AiErrorCode.unavailable : null,
          ),
        );
        finish();
      case AiStreamError(:final code, :final message):
        if (code == AiErrorCode.declined) {
          // Partial text of a refusal is never kept, copied or resent.
          _update(
            id,
            (m) => m.copyWith(
              text: message ?? ChatCopy.declinedFallback,
              status: ChatMessageStatus.declined,
            ),
          );
        } else {
          // In the stream, rate_limited means every provider was busy, not
          // that the user sent too much: word it as an outage.
          _fail(
            id,
            code == AiErrorCode.rateLimited ? AiErrorCode.unavailable : code,
            message,
          );
        }
        finish();
    }
  }

  void _fail(String id, AiErrorCode code, [String? serverMessage]) {
    _update(
      id,
      (m) => ChatMessage(
        id: m.id,
        isUser: false,
        text: '',
        createdAt: m.createdAt,
        status: ChatMessageStatus.error,
        provider: m.provider,
        errorCode: code,
        serverMessage: serverMessage,
      ),
    );
    if (code == AiErrorCode.consentRequired) {
      state = state.copyWith(consentRequired: true);
    }
  }

  void _update(String id, ChatMessage Function(ChatMessage) change) {
    state = state.copyWith(
      messages: [for (final m in state.messages) m.id == id ? change(m) : m],
    );
  }

  String _newId(String kind) =>
      '$kind-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  List<ChatMessage> _load(String uid) {
    try {
      final raw = ref
          .read(sharedPreferencesProvider)
          .getString(UserPrefs.key(uid, historyPref));
      if (raw == null) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return _trimmed([
        for (final item in decoded) ?ChatMessage.fromJson(item),
      ]);
    } on Object catch (e) {
      AppLogger.warn('Could not restore the chat history', e.runtimeType);
      return const [];
    }
  }

  void _persist() {
    final uid = _uid;
    if (uid == null || !ref.mounted) return;
    final messages = _trimmed(state.messages);
    final prefs = ref.read(sharedPreferencesProvider);
    final key = UserPrefs.key(uid, historyPref);
    unawaited(
      prefs
          .setString(key, jsonEncode([for (final m in messages) m.toJson()]))
          .then<void>(
            (_) {},
            onError: (Object e) => AppLogger.warn(
              'Could not save the chat history',
              e.runtimeType,
            ),
          ),
    );
  }

  /// The newest [maxStoredMessages], starting with a question.
  static List<ChatMessage> _trimmed(List<ChatMessage> messages) {
    var start = messages.length > maxStoredMessages
        ? messages.length - maxStoredMessages
        : 0;
    while (start < messages.length && !messages[start].isUser) {
      start++;
    }
    return start == 0 ? messages : messages.sublist(start);
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);
