/**
 * Server-Sent Events: an encoder and writable stream for responses (with keep-alive pings) and a
 * spec-compliant parser for reading upstream provider streams.
 */
import { systemTimers, type TimerId, type Timers } from "./clock.ts";

/** Response headers for an SSE stream. */
export const SSE_HEADERS: Readonly<Record<string, string>> = {
  "content-type": "text/event-stream; charset=utf-8",
  "cache-control": "no-cache, no-store, no-transform",
  "x-content-type-options": "nosniff",
  // Disables proxy buffering so tokens reach the app immediately.
  "x-accel-buffering": "no",
};

/** Default interval between `: ping` comments. */
export const DEFAULT_PING_INTERVAL_MS = 15_000;

const EVENT_NAME = /^[A-Za-z0-9_.-]{1,64}$/;

/**
 * Encodes one event as `event: <name>\ndata: <json>\n\n`. `JSON.stringify` escapes newlines, so
 * the payload is always a single `data:` line.
 */
export function encodeSseEvent(event: string, data: unknown): string {
  if (!EVENT_NAME.test(event)) throw new TypeError("Invalid SSE event name");
  const json = JSON.stringify(data ?? null);
  return `event: ${event}\ndata: ${json}\n\n`;
}

/** Encodes a comment line (ignored by clients), e.g. `: ping\n\n`. Line breaks are removed. */
export function encodeSseComment(text: string): string {
  return `: ${text.replace(/[\r\n]+/g, " ")}\n\n`;
}

/** Writes to an SSE response stream. All methods are no-ops once the stream is closed. */
export interface SseWriter {
  /** True after {@link SseWriter.close} or after the client disconnected. */
  readonly closed: boolean;
  /** Sends a named event with a JSON payload. Returns false if the stream is closed. */
  event(name: string, data: unknown): boolean;
  /** Sends a comment line. Returns false if the stream is closed. */
  comment(text: string): boolean;
  /** Stops pings and ends the stream. Safe to call more than once. */
  close(): void;
}

/** Options for {@link createSseStream}. */
export interface SseStreamOptions {
  /** Interval for `: ping` comments; 0 disables pings. Default 15 000 ms. */
  pingIntervalMs?: number;
  /** Injected timers (tests). */
  timers?: Pick<Timers, "setInterval" | "clearInterval">;
  /** Called once if the client disconnects (the response body is cancelled). */
  onCancel?: (reason: unknown) => void;
}

/** A response body plus the writer that feeds it. */
export interface SseStream {
  stream: ReadableStream<Uint8Array>;
  writer: SseWriter;
}

/** Creates an SSE body that emits `: ping` comments until closed or cancelled. */
export function createSseStream(options: SseStreamOptions = {}): SseStream {
  const timers = options.timers ?? systemTimers;
  const interval = options.pingIntervalMs ?? DEFAULT_PING_INTERVAL_MS;
  const encoder = new TextEncoder();
  let controller: ReadableStreamDefaultController<Uint8Array> | undefined;
  let closed = false;
  let pingId: TimerId | undefined;

  const stop = (): void => {
    closed = true;
    if (pingId !== undefined) timers.clearInterval(pingId);
    pingId = undefined;
  };

  const write = (text: string): boolean => {
    if (closed || controller === undefined) return false;
    try {
      controller.enqueue(encoder.encode(text));
      return true;
    } catch {
      stop();
      return false;
    }
  };

  const stream = new ReadableStream<Uint8Array>({
    start(c) {
      controller = c;
      if (interval > 0) {
        pingId = timers.setInterval(() => write(encodeSseComment("ping")), interval);
      }
    },
    cancel(reason) {
      if (closed) return;
      stop();
      options.onCancel?.(reason);
    },
  });

  const writer: SseWriter = {
    get closed() {
      return closed;
    },
    event: (name, data) => write(encodeSseEvent(name, data)),
    comment: (text) => write(encodeSseComment(text)),
    close() {
      if (closed) return;
      stop();
      try {
        controller?.close();
      } catch {
        // Already closed or errored.
      }
    },
  };

  return { stream, writer };
}

/** Wraps an SSE body in a 200 response with {@link SSE_HEADERS}. */
export function sseResponse(body: ReadableStream<Uint8Array>, headers: HeadersInit = {}): Response {
  const merged = new Headers(SSE_HEADERS);
  new Headers(headers).forEach((value, key) => merged.set(key, value));
  return new Response(body, { status: 200, headers: merged });
}

// ---------------------------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------------------------

/** One dispatched SSE message. */
export interface SseMessage {
  /** The `event:` field, or `"message"` when absent. */
  event: string;
  /** All `data:` lines joined with `\n`. */
  data: string;
  /** The last `id:` field seen, if any. */
  id?: string;
}

/** Options for {@link parseSse}. */
export interface ParseSseOptions {
  /** Aborting cancels the underlying body and rejects with the signal's reason. */
  signal?: AbortSignal;
  /** Maximum buffered characters for one line or event (default 1 MiB). */
  maxBufferChars?: number;
}

/** Thrown by {@link parseSse} when a line or event exceeds `maxBufferChars`. */
export class SseOverflowError extends Error {
  constructor() {
    super("SSE line or event too large");
    this.name = "SseOverflowError";
  }
}

/**
 * Parses an SSE byte stream per the WHATWG spec (CRLF/CR/LF line endings, comments, multi-line
 * data, optional single space after the colon). Unlike the spec, a final event that is not
 * followed by a blank line is still dispatched at end of stream, so a provider that omits the
 * trailing blank line does not lose its last event. Breaking out of the loop cancels the body.
 */
export async function* parseSse(
  body: ReadableStream<Uint8Array>,
  options: ParseSseOptions = {},
): AsyncGenerator<SseMessage, void, undefined> {
  const { signal } = options;
  const maxChars = options.maxBufferChars ?? 1024 * 1024;
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let eventName = "";
  let data: string[] = [];
  let dataChars = 0;
  let lastId: string | undefined;
  let finished = false;

  const onAbort = (): void => {
    reader.cancel(signal?.reason).catch(() => {});
  };
  signal?.addEventListener("abort", onAbort, { once: true });

  const take = (): SseMessage | undefined => {
    const message = data.length > 0
      ? {
        event: eventName || "message",
        data: data.join("\n"),
        ...(lastId !== undefined ? { id: lastId } : {}),
      }
      : undefined;
    eventName = "";
    data = [];
    dataChars = 0;
    return message;
  };

  const processLine = (line: string): SseMessage | undefined => {
    if (line === "") return take();
    if (line.startsWith(":")) return undefined;
    const colon = line.indexOf(":");
    const field = colon === -1 ? line : line.slice(0, colon);
    let value = colon === -1 ? "" : line.slice(colon + 1);
    if (value.startsWith(" ")) value = value.slice(1);
    switch (field) {
      case "event":
        eventName = value;
        break;
      case "data":
        dataChars += value.length + 1;
        if (dataChars > maxChars) throw new SseOverflowError();
        data.push(value);
        break;
      case "id":
        if (!value.includes("\0")) lastId = value;
        break;
      default:
        break; // `retry` and unknown fields are ignored.
    }
    return undefined;
  };

  try {
    while (true) {
      signal?.throwIfAborted();
      const { done, value } = await reader.read();
      signal?.throwIfAborted();
      if (done) {
        buffer += decoder.decode();
      } else {
        buffer += decoder.decode(value, { stream: true });
      }

      // Split complete lines; keep a trailing "\r" until we know whether "\n" follows.
      let start = 0;
      for (let i = 0; i < buffer.length; i++) {
        const ch = buffer.charCodeAt(i);
        if (ch !== 10 && ch !== 13) continue;
        if (ch === 13 && i === buffer.length - 1 && !done) break;
        const line = buffer.slice(start, i);
        if (ch === 13 && buffer.charCodeAt(i + 1) === 10) i++;
        start = i + 1;
        const message = processLine(line);
        if (message) yield message;
      }
      buffer = buffer.slice(start);
      if (buffer.length > maxChars) throw new SseOverflowError();

      if (done) {
        if (buffer !== "") {
          const message = processLine(buffer);
          buffer = "";
          if (message) yield message;
        }
        const pending = take();
        if (pending) yield pending;
        finished = true;
        return;
      }
    }
  } finally {
    signal?.removeEventListener("abort", onAbort);
    if (!finished) await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}
