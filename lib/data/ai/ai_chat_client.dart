import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_failure.dart';
import '../../core/logging/app_logger.dart';
import '../supabase_client_provider.dart';
import 'ai_chat_models.dart';
import 'sse_parser.dart';

/// Streams one assistant answer.
abstract interface class AiChatApi {
  /// Sends [request] and emits the answer's events, ending with exactly one
  /// [AiDone], [AiInterrupted] or [AiStreamError]. Failures before the
  /// stream opens are emitted as an [AiChatException] error. Completing
  /// [abortTrigger] cancels the network request.
  Stream<AiStreamEvent> stream(
    AiChatRequest request, {
    Future<void>? abortTrigger,
  });
}

/// Access tokens for the signed-in user.
abstract interface class AiSessionSource {
  /// A token that is not known to be expired, or null when signed out.
  Future<String?> accessToken();

  /// Refreshes the session and returns the new token (null on failure).
  Future<String?> refresh();
}

/// [AiSessionSource] backed by the Supabase auth client.
class SupabaseAiSessionSource implements AiSessionSource {
  SupabaseAiSessionSource(this._client);

  final SupabaseClient _client;

  @override
  Future<String?> accessToken() async {
    final session = _client.auth.currentSession;
    if (session == null) return null;
    if (session.isExpired) return refresh();
    return session.accessToken;
  }

  @override
  Future<String?> refresh() async {
    try {
      final result = await _client.auth.refreshSession();
      return result.session?.accessToken;
    } on AuthException catch (e) {
      AppLogger.warn('Session refresh for the assistant failed', e.code);
      return null;
    }
  }
}

/// The SSE client for `POST /functions/v1/ai-chat`.
class AiChatClient implements AiChatApi {
  AiChatClient({
    required this.endpoint,
    required this.anonKey,
    required this.session,
    http.Client Function()? httpClientFactory,
    this.connectTimeout = const Duration(seconds: 20),
    this.idleTimeout = const Duration(seconds: 45),
    this.overallTimeout = const Duration(seconds: 150),
  }) : _httpClientFactory = httpClientFactory ?? http.Client.new;

  /// The function URL for a project base URL.
  static Uri endpointFor(String supabaseUrl) {
    final base = supabaseUrl.endsWith('/')
        ? supabaseUrl.substring(0, supabaseUrl.length - 1)
        : supabaseUrl;
    return Uri.parse('$base/functions/v1/ai-chat');
  }

  final Uri endpoint;
  final String anonKey;
  final AiSessionSource session;
  final http.Client Function() _httpClientFactory;

  /// Time allowed until the response headers arrive.
  final Duration connectTimeout;

  /// Longest silence allowed on an open stream (the server pings every
  /// 15 s while it waits).
  final Duration idleTimeout;

  /// Longest time an open stream may run, pings included. Text received
  /// before it ends the stream is kept as an interrupted answer.
  final Duration overallTimeout;

  @override
  Stream<AiStreamEvent> stream(
    AiChatRequest request, {
    Future<void>? abortTrigger,
  }) {
    final controller = StreamController<AiStreamEvent>();
    final abort = Completer<void>();
    void doAbort() {
      if (!abort.isCompleted) abort.complete();
    }

    unawaited(abortTrigger?.then((_) => doAbort()));
    final client = _httpClientFactory();
    var cancelled = false;
    StreamSubscription<SseEvent>? events;
    // Completed by the pump, or by onCancel: a cancelled subscription fires
    // no onDone, and run() must still reach its finally block.
    final pumped = Completer<void>();

    Future<void> finish() async {
      doAbort();
      client.close();
      if (!controller.isClosed) await controller.close();
    }

    void fail(AiChatException e) {
      if (!controller.isClosed && !cancelled) controller.addError(e);
    }

    Future<void> run() async {
      try {
        var token = await session.accessToken();
        if (token == null) {
          token = await session.refresh();
          if (token == null) {
            fail(const AiChatException(AiErrorCode.unauthorized));
            return;
          }
        }
        var response = await _open(client, request, token, abort);
        if (response.statusCode == 401) {
          await _drain(response);
          final refreshed = await session.refresh();
          if (refreshed == null) {
            fail(const AiChatException(AiErrorCode.unauthorized));
            return;
          }
          response = await _open(client, request, refreshed, abort);
        }
        if (response.statusCode != 200) {
          fail(await _httpError(response));
          return;
        }
        if (cancelled) return;
        await _pump(response, controller, abort, pumped, (s) => events = s);
      } on AiChatException catch (e) {
        fail(e);
      } on Object catch (e, s) {
        if (abort.isCompleted || cancelled) {
          fail(const AiChatException(AiErrorCode.aborted));
        } else {
          fail(_transportError(e, s));
        }
      } finally {
        await finish();
      }
    }

    controller.onListen = () {
      unawaited(run());
    };
    controller.onCancel = () async {
      cancelled = true;
      doAbort();
      await events?.cancel();
      if (!pumped.isCompleted) pumped.complete();
      client.close();
    };
    return controller.stream;
  }

  Future<http.StreamedResponse> _open(
    http.Client client,
    AiChatRequest request,
    String token,
    Completer<void> abort,
  ) async {
    final req =
        http.AbortableRequest('POST', endpoint, abortTrigger: abort.future)
          ..headers.addAll({
            'authorization': 'Bearer $token',
            'apikey': anonKey,
            'content-type': 'application/json; charset=utf-8',
            'accept': 'text/event-stream',
          })
          ..body = request.encode();
    try {
      return await client.send(req).timeout(connectTimeout);
    } on TimeoutException {
      if (!abort.isCompleted) abort.complete();
      throw const AiChatException(AiErrorCode.timeout);
    }
  }

  Future<void> _pump(
    http.StreamedResponse response,
    StreamController<AiStreamEvent> out,
    Completer<void> abort,
    Completer<void> done,
    void Function(StreamSubscription<SseEvent>) onSubscription,
  ) {
    var sawText = false;
    var terminal = false;

    void emit(AiStreamEvent e) {
      if (out.isClosed || terminal) return;
      if (e is AiDelta) sawText = true;
      if (e is AiDone || e is AiInterrupted || e is AiStreamError) {
        terminal = true;
      }
      out.add(e);
    }

    void endWith(AiErrorCode code) {
      if (terminal || out.isClosed) return;
      if (sawText) {
        emit(
          AiInterrupted(
            reason: code == AiErrorCode.timeout ? 'timeout' : 'error',
          ),
        );
      } else {
        out.addError(AiChatException(code));
        terminal = true;
      }
    }

    final idle = response.stream.timeout(
      idleTimeout,
      onTimeout: (sink) {
        if (!abort.isCompleted) abort.complete();
        sink
          ..addError(const AiChatException(AiErrorCode.timeout))
          ..close();
      },
    );
    late final StreamSubscription<SseEvent> sub;
    final overall = Timer(overallTimeout, () {
      if (terminal || out.isClosed) return;
      if (!abort.isCompleted) abort.complete();
      endWith(AiErrorCode.timeout);
      unawaited(sub.cancel());
      if (!done.isCompleted) done.complete();
    });
    sub = decodeSse(idle).listen(
      (event) {
        final mapped = parseAiEvent(event);
        if (mapped != null) emit(mapped);
        if (terminal) {
          unawaited(sub.cancel());
          if (!done.isCompleted) done.complete();
        }
      },
      onError: (Object e, StackTrace s) {
        if (terminal) return;
        if (abort.isCompleted && e is! AiChatException) {
          endWith(AiErrorCode.aborted);
        } else if (e is AiChatException) {
          endWith(e.code);
        } else if (e is SseOverflowException) {
          endWith(AiErrorCode.unavailable);
        } else {
          endWith(_transportError(e, s).code);
        }
        unawaited(sub.cancel());
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        // The connection closed without a terminal event.
        endWith(AiErrorCode.network);
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: false,
    );
    onSubscription(sub);
    return done.future.whenComplete(overall.cancel);
  }

  static Future<void> _drain(http.StreamedResponse response) async {
    try {
      await response.stream.drain<void>();
    } on Object {
      // Nothing to keep from a rejected response.
    }
  }

  static Future<AiChatException> _httpError(
    http.StreamedResponse response,
  ) async {
    String? code;
    String? reason;
    String? message;
    try {
      final body = await response.stream.bytesToString().timeout(
        const Duration(seconds: 10),
      );
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        final err = decoded['error'] as Map;
        if (err['code'] is String) code = err['code'] as String;
        if (err['reason'] is String) reason = err['reason'] as String;
        if (err['message'] is String) message = err['message'] as String;
      }
    } on Object {
      // A body that is not the standard error shape: use the status.
    }
    final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
    final status = response.statusCode;
    final mapped =
        AiErrorCode.fromWire(code) ??
        AiErrorCode.fromWire(reason) ??
        switch (status) {
          400 || 422 => AiErrorCode.invalidRequest,
          401 => AiErrorCode.unauthorized,
          413 => AiErrorCode.tooLong,
          429 => AiErrorCode.rateLimited,
          408 || 504 => AiErrorCode.timeout,
          >= 500 => AiErrorCode.unavailable,
          _ => AiErrorCode.unknown,
        };
    final code429 = status == 429 && reason == 'quota_exceeded'
        ? AiErrorCode.quotaExceeded
        : mapped;
    if (code429 == AiErrorCode.unknown) {
      AppLogger.warn('Unexpected assistant response', status);
    }
    return AiChatException(
      code429,
      serverMessage: message,
      retryAfter: retryAfter == null ? null : Duration(seconds: retryAfter),
    );
  }

  static AiChatException _transportError(Object error, StackTrace stack) {
    if (error is AiChatException) return error;
    if (error is http.RequestAbortedException) {
      return const AiChatException(AiErrorCode.aborted);
    }
    final failure = ErrorMapper.map(error, stack);
    return AiChatException(switch (failure) {
      OfflineFailure() => AiErrorCode.offline,
      TimeoutFailure() => AiErrorCode.timeout,
      NetworkFailure() => AiErrorCode.network,
      _ => AiErrorCode.unknown,
    });
  }
}

/// Maps one SSE event of the `ai-chat` stream; null for events to ignore.
AiStreamEvent? parseAiEvent(SseEvent event) {
  Map<Object?, Object?> data;
  try {
    final decoded = jsonDecode(event.data);
    if (decoded is! Map) return null;
    data = decoded;
  } on FormatException {
    return null;
  }
  String? str(String key) {
    final v = data[key];
    return v is String && v.trim().isNotEmpty ? v : null;
  }

  switch (event.event) {
    case 'meta':
      return AiMeta(AiProvider.fromWire(data['provider']));
    case 'delta':
      final text = data['text'];
      return text is String && text.isNotEmpty ? AiDelta(text) : null;
    case 'done':
      return AiDone(truncated: data['truncated'] == true);
    case 'interrupted':
      return AiInterrupted(reason: str('reason'), message: str('message'));
    case 'error':
      return AiStreamError(
        AiErrorCode.fromWire(data['code']) ?? AiErrorCode.unavailable,
        message: str('message'),
        discardPartial: data['discard_partial'] == true,
      );
    default:
      return null;
  }
}

/// The assistant transport. Override in tests.
final aiChatApiProvider = Provider<AiChatApi>((ref) {
  const config = AppConfig.environment;
  return AiChatClient(
    endpoint: AiChatClient.endpointFor(config.supabaseUrl),
    anonKey: config.supabaseAnonKey,
    session: SupabaseAiSessionSource(ref.watch(supabaseClientProvider)),
  );
});
