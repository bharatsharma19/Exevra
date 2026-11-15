import 'dart:async';
import 'dart:convert';

/// One dispatched Server-Sent Event.
class SseEvent {
  const SseEvent({required this.event, required this.data, this.id});

  /// The `event:` field, `message` when the server sent none.
  final String event;

  /// All `data:` lines of the event joined with `\n`.
  final String data;

  /// The last `id:` field seen, if any.
  final String? id;

  @override
  bool operator ==(Object other) =>
      other is SseEvent &&
      other.event == event &&
      other.data == data &&
      other.id == id;

  @override
  int get hashCode => Object.hash(event, data, id);

  @override
  String toString() => 'SseEvent($event, ${data.length} chars)';
}

/// Thrown when one line or one event's data grows past
/// [SseParser.maxBufferLength].
class SseOverflowException implements Exception {
  const SseOverflowException();

  @override
  String toString() => 'SseOverflowException';
}

/// Incremental parser for the `text/event-stream` format (WHATWG HTML,
/// "Server-sent events"), independent of any transport.
///
/// Feed decoded text with [add] in chunks of any size; complete events are
/// returned as soon as their terminating blank line arrives. Handles `\n`,
/// `\r\n` and lone `\r` line endings (also when a `\r\n` pair is split
/// across two chunks), multi-line `data`, a leading byte-order mark,
/// comment lines (`: ping`), fields without a value and unknown fields.
class SseParser {
  SseParser({this.maxBufferLength = 1 << 20});

  /// Upper bound for one line and for one event's data, in UTF-16 units.
  final int maxBufferLength;

  final StringBuffer _line = StringBuffer();
  final StringBuffer _data = StringBuffer();
  String _event = '';
  String? _lastId;
  bool _hasData = false;
  bool _skipLf = false;
  bool _atStart = true;

  /// Number of comment lines seen (keep-alive pings).
  int comments = 0;

  /// Parses [chunk] and returns the events it completed.
  List<SseEvent> add(String chunk) {
    final out = <SseEvent>[];
    var start = 0;
    if (_atStart && chunk.isNotEmpty) {
      _atStart = false;
      if (chunk.codeUnitAt(0) == 0xFEFF) start = 1;
    }
    var segmentStart = start;
    for (var i = start; i < chunk.length; i++) {
      final c = chunk.codeUnitAt(i);
      if (c == 0x0A && _skipLf) {
        _skipLf = false;
        segmentStart = i + 1;
        continue;
      }
      _skipLf = false;
      if (c == 0x0A || c == 0x0D) {
        _appendLine(chunk, segmentStart, i);
        _skipLf = c == 0x0D;
        _processLine(_line.toString(), out);
        _line.clear();
        segmentStart = i + 1;
      }
    }
    _appendLine(chunk, segmentStart, chunk.length);
    return out;
  }

  /// Ends the input. A trailing event without its blank line is discarded,
  /// as the specification requires.
  void close() {
    _line.clear();
    _resetEvent();
  }

  void _appendLine(String chunk, int from, int to) {
    if (to <= from) return;
    if (_line.length + (to - from) > maxBufferLength) {
      throw const SseOverflowException();
    }
    _line.write(chunk.substring(from, to));
  }

  void _processLine(String line, List<SseEvent> out) {
    if (line.isEmpty) {
      if (_hasData) {
        out.add(
          SseEvent(
            event: _event.isEmpty ? 'message' : _event,
            data: _data.toString(),
            id: _lastId,
          ),
        );
      }
      _resetEvent();
      return;
    }
    if (line.codeUnitAt(0) == 0x3A) {
      comments++;
      return;
    }
    final colon = line.indexOf(':');
    final String field;
    var value = '';
    if (colon < 0) {
      field = line;
    } else {
      field = line.substring(0, colon);
      value = line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
    }
    switch (field) {
      case 'event':
        _event = value;
      case 'data':
        if (_data.length + value.length + 1 > maxBufferLength) {
          throw const SseOverflowException();
        }
        if (_hasData) _data.write('\n');
        _data.write(value);
        _hasData = true;
      case 'id':
        if (!value.contains('\u0000')) _lastId = value;
      default:
        // `retry` and unknown fields are ignored.
        break;
    }
  }

  void _resetEvent() {
    _data.clear();
    _event = '';
    _hasData = false;
  }
}

/// Turns a byte stream into [SseEvent]s (UTF-8, chunk boundaries anywhere,
/// also inside multi-byte characters).
Stream<SseEvent> decodeSse(Stream<List<int>> bytes, {SseParser? parser}) {
  final p = parser ?? SseParser();
  return bytes
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(
        StreamTransformer<String, SseEvent>.fromHandlers(
          handleData: (chunk, sink) {
            try {
              p.add(chunk).forEach(sink.add);
            } on SseOverflowException catch (e, s) {
              sink.addError(e, s);
            }
          },
          handleDone: (sink) {
            p.close();
            sink.close();
          },
        ),
      );
}
