import 'dart:async';
import 'dart:convert';

import 'package:expense_manager/data/ai/sse_parser.dart';
import 'package:flutter_test/flutter_test.dart';

List<SseEvent> parseAll(List<String> chunks, {SseParser? parser}) {
  final p = parser ?? SseParser();
  return [for (final c in chunks) ...p.add(c)];
}

void main() {
  group('SseParser', () {
    test('parses the server event shape with LF endings', () {
      final events = parseAll([
        'event: meta\ndata: {"provider":"claude"}\n\n'
            'event: delta\ndata: {"text":"Hi"}\n\n'
            'event: done\ndata: {"truncated":false}\n\n',
      ]);
      expect(events.map((e) => e.event), ['meta', 'delta', 'done']);
      expect(events[1].data, '{"text":"Hi"}');
    });

    test('handles CRLF and lone CR line endings', () {
      expect(parseAll(['event: a\r\ndata: 1\r\n\r\n']), [
        const SseEvent(event: 'a', data: '1'),
      ]);
      expect(parseAll(['event: b\rdata: 2\r\r']), [
        const SseEvent(event: 'b', data: '2'),
      ]);
    });

    test('a CRLF pair split across chunks is one line break', () {
      final events = parseAll(['event: a\r', '\ndata: 1\r', '\n\r', '\n']);
      expect(events, [const SseEvent(event: 'a', data: '1')]);
    });

    test('events split at every possible boundary parse the same', () {
      const raw =
          'event: delta\r\ndata: {"text":"a"}\r\n\r\n: ping\n\n'
          'event: done\ndata: {"truncated":true}\n\n';
      final whole = parseAll([raw]);
      for (var i = 0; i <= raw.length; i++) {
        expect(
          parseAll([raw.substring(0, i), raw.substring(i)]),
          whole,
          reason: 'split at $i',
        );
      }
      expect(parseAll([for (final c in raw.split('')) c]), whole);
    });

    test('joins multi-line data with newlines', () {
      expect(parseAll(['data: one\ndata: two\ndata:\n\n']), [
        const SseEvent(event: 'message', data: 'one\ntwo\n'),
      ]);
    });

    test('ignores comments and counts them as pings', () {
      final parser = SseParser();
      final events = parseAll([
        ': ping\n\n',
        ':\n',
        'event: delta\ndata: x\n\n',
      ], parser: parser);
      expect(events, [const SseEvent(event: 'delta', data: 'x')]);
      expect(parser.comments, 2);
    });

    test('value without a space after the colon, and unknown fields', () {
      expect(parseAll(['event:meta\nretry: 10\nfoo: bar\ndata:{}\n\n']), [
        const SseEvent(event: 'meta', data: '{}'),
      ]);
    });

    test('strips a leading byte-order mark and keeps the last id', () {
      expect(parseAll(['﻿id: 7\ndata: a\n\n']), [
        const SseEvent(event: 'message', data: 'a', id: '7'),
      ]);
    });

    test('an event without data is not dispatched', () {
      expect(parseAll(['event: meta\n\n']), isEmpty);
    });

    test('a trailing event without its blank line is dropped on close', () {
      final parser = SseParser();
      expect(parser.add('event: delta\ndata: x\n'), isEmpty);
      parser.close();
      expect(parser.add('\n'), isEmpty);
    });

    test('rejects a line over the buffer limit', () {
      final parser = SseParser(maxBufferLength: 16);
      expect(
        () => parser.add('data: ${'x' * 40}'),
        throwsA(isA<SseOverflowException>()),
      );
    });
  });

  group('decodeSse', () {
    test('decodes UTF-8 split inside a multi-byte character', () async {
      final bytes = utf8.encode('event: delta\ndata: {"text":"₹ 12 😀"}\n\n');
      final chunks = [
        for (final b in bytes) <int>[b],
      ];
      final events = await decodeSse(Stream.fromIterable(chunks)).toList();
      expect(events.single.data, '{"text":"₹ 12 😀"}');
    });

    test('surfaces overflow as a stream error', () async {
      final stream = decodeSse(
        Stream.value(utf8.encode('data: ${'x' * 100}\n\n')),
        parser: SseParser(maxBufferLength: 10),
      );
      await expectLater(stream, emitsError(isA<SseOverflowException>()));
    });
  });
}
