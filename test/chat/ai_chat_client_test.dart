import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:expense_manager/data/ai/ai_chat_client.dart';
import 'package:expense_manager/data/ai/ai_chat_models.dart';
import 'package:expense_manager/data/ai/sse_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class FakeSession implements AiSessionSource {
  FakeSession({this.token = 't1', this.refreshed = 't2'});

  String? token;
  String? refreshed;
  int refreshCalls = 0;

  @override
  Future<String?> accessToken() async => token;

  @override
  Future<String?> refresh() async {
    refreshCalls++;
    return refreshed;
  }
}

/// A response the fake server sends: a status, headers and body chunks
/// (a null chunk leaves the body open).
class Reply {
  Reply(this.status, {this.chunks = const [], this.headers = const {}});

  Reply.json(int status, Map<String, Object?> body, {Map<String, String>? h})
    : this(status, chunks: [jsonEncode(body)], headers: h ?? const {});

  final int status;
  final List<String?> chunks;
  final Map<String, String> headers;
}

class FakeHttp extends http.BaseClient {
  FakeHttp(this.replies);

  final List<Object> replies;
  final List<http.Request> requests = [];
  final List<StreamController<List<int>>> bodies = [];
  bool aborted = false;
  int closes = 0;

  @override
  void close() => closes++;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request as http.Request);
    final reply = replies.removeAt(0);
    if (reply is Exception) throw reply;
    reply as Reply;
    final body = StreamController<List<int>>();
    bodies.add(body);
    if (request is http.Abortable) {
      unawaited(
        (request as http.Abortable).abortTrigger?.then((_) {
          aborted = true;
          if (!body.isClosed) {
            body.addError(http.RequestAbortedException(request.url));
            unawaited(body.close());
          }
        }),
      );
    }
    var open = false;
    for (final c in reply.chunks) {
      if (c == null) {
        open = true;
        break;
      }
      body.add(utf8.encode(c));
    }
    if (!open) unawaited(body.close());
    return http.StreamedResponse(
      body.stream,
      reply.status,
      headers: reply.headers,
    );
  }
}

const request = AiChatRequest(
  messages: [AiTurn.user('How much on food?')],
  timeZone: 'Asia/Kolkata',
  locale: 'en-IN',
);

String sse(String event, Map<String, Object?> data) =>
    'event: $event\ndata: ${jsonEncode(data)}\n\n';

AiChatClient clientFor(
  FakeHttp http, {
  FakeSession? session,
  Duration idle = const Duration(seconds: 45),
  Duration overall = const Duration(seconds: 150),
}) => AiChatClient(
  endpoint: AiChatClient.endpointFor('https://example.supabase.co/'),
  anonKey: 'anon',
  session: session ?? FakeSession(),
  httpClientFactory: () => http,
  idleTimeout: idle,
  overallTimeout: overall,
);

Future<AiChatException> errorOf(Stream<AiStreamEvent> stream) async {
  try {
    await stream.toList();
  } on AiChatException catch (e) {
    return e;
  }
  fail('expected an AiChatException');
}

void main() {
  test('builds the endpoint and sends auth headers and the body', () async {
    final fake = FakeHttp([
      Reply(
        200,
        chunks: [
          sse('meta', {'provider': 'claude', 'request_id': 'r'}),
          'event: delta\r\ndata: {"text":"You spent "}\r\n\r\n',
          ': ping\n\n',
          sse('delta', {'text': '₹1,200.'}),
          sse('done', {'truncated': false}),
        ],
      ),
    ]);
    final events = await clientFor(fake).stream(request).toList();

    final sent = fake.requests.single;
    expect(
      sent.url.toString(),
      'https://example.supabase.co/functions/v1/ai-chat',
    );
    expect(sent.method, 'POST');
    expect(sent.headers['authorization'], 'Bearer t1');
    expect(sent.headers['apikey'], 'anon');
    expect(jsonDecode(sent.body), {
      'messages': [
        {'role': 'user', 'content': 'How much on food?'},
      ],
      'tz': 'Asia/Kolkata',
      'locale': 'en-IN',
      'days': 90,
    });
    expect(events, hasLength(4));
    expect((events[0] as AiMeta).provider, AiProvider.claude);
    expect((events[1] as AiDelta).text, 'You spent ');
    expect((events[2] as AiDelta).text, '₹1,200.');
    expect((events[3] as AiDone).truncated, isFalse);
  });

  test('refreshes the session once on 401 and retries', () async {
    final session = FakeSession();
    final fake = FakeHttp([
      Reply.json(401, {
        'error': {'code': 'unauthorized', 'message': 'x'},
      }),
      Reply(
        200,
        chunks: [
          sse('error', {'code': 'unavailable'}),
        ],
      ),
    ]);
    final events = await clientFor(
      fake,
      session: session,
    ).stream(request).toList();
    expect(session.refreshCalls, 1);
    expect(fake.requests.map((r) => r.headers['authorization']), [
      'Bearer t1',
      'Bearer t2',
    ]);
    expect((events.single as AiStreamError).code, AiErrorCode.unavailable);
  });

  test('a second 401 is unauthorized', () async {
    final fake = FakeHttp([
      Reply.json(401, {
        'error': {'code': 'unauthorized'},
      }),
      Reply.json(401, {
        'error': {'code': 'unauthorized'},
      }),
    ]);
    final e = await errorOf(clientFor(fake).stream(request));
    expect(e.code, AiErrorCode.unauthorized);
    expect(fake.requests, hasLength(2));
  });

  test('no session and no refresh is unauthorized without a request', () async {
    final fake = FakeHttp([]);
    final e = await errorOf(
      clientFor(
        fake,
        session: FakeSession(token: null, refreshed: null),
      ).stream(request),
    );
    expect(e.code, AiErrorCode.unauthorized);
    expect(fake.requests, isEmpty);
  });

  group('pre-stream HTTP errors', () {
    final cases = <(int, Map<String, Object?>, AiErrorCode)>[
      (403, {'code': 'consent_required'}, AiErrorCode.consentRequired),
      (400, {'code': 'invalid_request'}, AiErrorCode.invalidRequest),
      (413, {'code': 'too_long'}, AiErrorCode.tooLong),
      (
        429,
        {'code': 'quota_exceeded', 'reason': 'quota_exceeded'},
        AiErrorCode.quotaExceeded,
      ),
      (
        429,
        {'code': 'rate_limited', 'reason': 'rate_limited'},
        AiErrorCode.rateLimited,
      ),
      (503, {'code': 'unavailable'}, AiErrorCode.unavailable),
      (500, {'code': 'internal'}, AiErrorCode.unavailable),
    ];
    for (final (status, error, code) in cases) {
      test('$status ${error['code']} -> ${code.name}', () async {
        final fake = FakeHttp([
          Reply.json(status, {'error': error}, h: {'retry-after': '60'}),
        ]);
        final e = await errorOf(clientFor(fake).stream(request));
        expect(e.code, code);
        expect(e.retryAfter, const Duration(seconds: 60));
      });
    }

    test('a non-JSON body falls back to the status', () async {
      final fake = FakeHttp([
        Reply(502, chunks: ['<html>bad gateway</html>']),
      ]);
      final e = await errorOf(clientFor(fake).stream(request));
      expect(e.code, AiErrorCode.unavailable);
    });
  });

  test('no connection is offline', () async {
    final fake = FakeHttp([
      const SocketException('Failed host lookup: example.supabase.co'),
    ]);
    final e = await errorOf(clientFor(fake).stream(request));
    expect(e.code, AiErrorCode.offline);
  });

  test('a stream that ends after text without a terminal event is '
      'interrupted', () async {
    final fake = FakeHttp([
      Reply(
        200,
        chunks: [
          sse('meta', {'provider': 'gemini'}),
          sse('delta', {'text': 'Partial'}),
        ],
      ),
    ]);
    final events = await clientFor(fake).stream(request).toList();
    expect((events.first as AiMeta).provider, AiProvider.gemini);
    expect(events.last, isA<AiInterrupted>());
  });

  test('a stream that ends before any text is a network error', () async {
    final fake = FakeHttp([
      Reply(200, chunks: [': ping\n\n']),
    ]);
    final e = await errorOf(clientFor(fake).stream(request));
    expect(e.code, AiErrorCode.network);
  });

  test('silence past the idle timeout is a timeout', () async {
    final fake = FakeHttp([
      Reply(200, chunks: [null]),
    ]);
    final e = await errorOf(
      clientFor(fake, idle: const Duration(milliseconds: 50)).stream(request),
    );
    expect(e.code, AiErrorCode.timeout);
    expect(fake.aborted, isTrue);
  });

  test('pings cannot keep a stream open past the overall timeout', () async {
    final fake = FakeHttp([
      Reply(200, chunks: [null]),
    ]);
    final client = clientFor(
      fake,
      idle: const Duration(milliseconds: 80),
      overall: const Duration(milliseconds: 200),
    );
    final pinger = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (fake.bodies.isNotEmpty && !fake.bodies.first.isClosed) {
        fake.bodies.first.add(utf8.encode(': ping\n\n'));
      }
    });
    addTearDown(pinger.cancel);
    final e = await errorOf(client.stream(request));
    expect(e.code, AiErrorCode.timeout);
    expect(fake.aborted, isTrue);
  });

  test('text before the overall timeout ends as interrupted', () async {
    final fake = FakeHttp([
      Reply(
        200,
        chunks: [
          sse('delta', {'text': 'Half'}),
          null,
        ],
      ),
    ]);
    final events = await clientFor(
      fake,
      overall: const Duration(milliseconds: 50),
    ).stream(request).toList();
    expect(events.whereType<AiDelta>().single.text, 'Half');
    expect((events.last as AiInterrupted).reason, 'timeout');
  });

  test('cancelling mid-stream lets the request finish', () async {
    final fake = FakeHttp([
      Reply(
        200,
        chunks: [
          sse('delta', {'text': 'Hi'}),
          null,
        ],
      ),
    ]);
    final first = Completer<void>();
    final sub = clientFor(fake).stream(request).listen((_) {
      if (!first.isCompleted) first.complete();
    });
    await first.future;
    await sub.cancel();
    await pumpEventQueue();
    // Once from onCancel, once from run()'s finally block.
    expect(fake.closes, 2);
    expect(fake.aborted, isTrue);
  });

  test('silence after text ends as interrupted (timeout)', () async {
    final fake = FakeHttp([
      Reply(
        200,
        chunks: [
          sse('delta', {'text': 'Half'}),
          null,
        ],
      ),
    ]);
    final events = await clientFor(
      fake,
      idle: const Duration(milliseconds: 50),
    ).stream(request).toList();
    expect((events.last as AiInterrupted).reason, 'timeout');
  });

  test('the abort trigger cancels the network request', () async {
    final fake = FakeHttp([
      Reply(
        200,
        chunks: [
          sse('delta', {'text': 'Hi'}),
          null,
        ],
      ),
    ]);
    final abort = Completer<void>();
    final received = <AiStreamEvent>[];
    final done = Completer<void>();
    clientFor(fake)
        .stream(request, abortTrigger: abort.future)
        .listen(received.add, onError: (_) {}, onDone: done.complete);
    await pumpEventQueue();
    expect(received.single, isA<AiDelta>());
    abort.complete();
    await done.future;
    expect(fake.aborted, isTrue);
    expect(received.whereType<AiDone>(), isEmpty);
  });

  test('ignores events after the terminal one', () async {
    final fake = FakeHttp([
      Reply(
        200,
        chunks: [
          sse('meta', {'provider': 'claude'}),
          sse('delta', {'text': 'A'}),
          sse('done', {'truncated': true}),
          sse('delta', {'text': 'late'}),
        ],
      ),
    ]);
    final events = await clientFor(fake).stream(request).toList();
    expect(events.last, isA<AiDone>());
    expect((events.last as AiDone).truncated, isTrue);
    expect(events.whereType<AiDelta>().map((e) => e.text), ['A']);
  });

  group('parseAiEvent', () {
    test('declined with discard_partial', () {
      final e =
          parseAiEvent(
                SseEvent(
                  event: 'error',
                  data: jsonEncode({
                    'code': 'declined',
                    'message': 'I can not help with that.',
                    'discard_partial': true,
                  }),
                ),
              )!
              as AiStreamError;
      expect(e.code, AiErrorCode.declined);
      expect(e.discardPartial, isTrue);
      expect(e.message, 'I can not help with that.');
    });

    test('interrupted carries reason and message', () {
      final e =
          parseAiEvent(
                const SseEvent(
                  event: 'interrupted',
                  data:
                      '{"code":"interrupted","reason":"timeout","message":"m"}',
                ),
              )!
              as AiInterrupted;
      expect(e.reason, 'timeout');
    });

    test('unknown provider has no label; raw model ids never pass', () {
      final e =
          parseAiEvent(
                const SseEvent(
                  event: 'meta',
                  data: '{"provider":"claude-haiku-5-5"}',
                ),
              )!
              as AiMeta;
      expect(e.provider, isNull);
    });

    test('bad JSON and unknown events are ignored', () {
      expect(
        parseAiEvent(const SseEvent(event: 'delta', data: '{nope')),
        isNull,
      );
      expect(parseAiEvent(const SseEvent(event: 'other', data: '{}')), isNull);
    });
  });
}
