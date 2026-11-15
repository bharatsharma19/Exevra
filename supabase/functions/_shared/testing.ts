/**
 * Test helpers shared by the functions' `*_test.ts` files. Never import this from runtime code.
 */
import type { Clock, Timers } from "./clock.ts";
import type { LogLevel, LogSink } from "./log.ts";

/** A clock that only moves when told to. */
export interface FakeClock extends Clock {
  advance(ms: number): void;
  set(ms: number): void;
}

/** Creates a {@link FakeClock} starting at `startMs`. */
export function fakeClock(startMs = 0): FakeClock {
  let now = startMs;
  return {
    now: () => now,
    advance: (ms) => {
      now += ms;
    },
    set: (ms) => {
      now = ms;
    },
  };
}

/** Manually driven timers. `tick(ms)` fires due callbacks in time order. */
export interface FakeTimers extends Timers {
  readonly clock: FakeClock;
  /** Advances time by `ms`, running every timer that becomes due. */
  tick(ms: number): void;
  /** Number of scheduled timers and intervals. */
  pending(): number;
}

/** Creates {@link FakeTimers} sharing a {@link FakeClock}. */
export function fakeTimers(startMs = 0): FakeTimers {
  const clock = fakeClock(startMs);
  let nextId = 1;
  const timers = new Map<number, { due: number; every?: number; fn: () => void }>();
  const add = (fn: () => void, ms: number, every?: number): number => {
    const id = nextId++;
    timers.set(id, { due: clock.now() + Math.max(0, ms), every, fn });
    return id;
  };
  const remove = (id: unknown): void => {
    if (typeof id === "number") timers.delete(id);
  };
  return {
    clock,
    setTimeout: (fn, ms) => add(fn, ms),
    clearTimeout: remove,
    setInterval: (fn, ms) => add(fn, ms, Math.max(1, ms)),
    clearInterval: remove,
    pending: () => timers.size,
    tick(ms) {
      const target = clock.now() + ms;
      while (true) {
        let nextIdDue: number | undefined;
        let nextDue = Infinity;
        for (const [id, t] of timers) {
          if (t.due <= target && t.due < nextDue) {
            nextDue = t.due;
            nextIdDue = id;
          }
        }
        if (nextIdDue === undefined) break;
        const timer = timers.get(nextIdDue);
        if (timer === undefined) break;
        clock.set(timer.due);
        if (timer.every !== undefined) timer.due += timer.every;
        else timers.delete(nextIdDue);
        timer.fn();
      }
      clock.set(target);
    },
  };
}

/** A ReadableStream that yields each string as one UTF-8 chunk, e.g. fake SSE bodies. */
export function streamFromChunks(chunks: readonly string[]): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  let i = 0;
  return new ReadableStream<Uint8Array>({
    pull(controller) {
      if (i < chunks.length) controller.enqueue(encoder.encode(chunks[i++]));
      else controller.close();
    },
  });
}

/** Reads a whole byte stream as text. */
export async function readAllText(stream: ReadableStream<Uint8Array>): Promise<string> {
  return await new Response(stream).text();
}

/** A recorded `fetch` call. */
export interface RecordedRequest {
  url: string;
  method: string;
  headers: Headers;
  body: string;
  signal: AbortSignal | null;
}

/** Handle returned by {@link mockFetch}. */
export interface FetchMock extends Disposable {
  readonly calls: RecordedRequest[];
  restore(): void;
}

/**
 * Replaces `globalThis.fetch` with `handler` until `restore()` (or `using` disposal). Every call
 * is recorded with its body read as text.
 */
export function mockFetch(
  handler: (req: RecordedRequest) => Response | Promise<Response>,
): FetchMock {
  const original = globalThis.fetch;
  const calls: RecordedRequest[] = [];
  globalThis.fetch = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const request = new Request(input, init);
    const recorded: RecordedRequest = {
      url: request.url,
      method: request.method,
      headers: request.headers,
      body: request.body === null ? "" : await request.text(),
      signal: init?.signal ?? (input instanceof Request ? input.signal : null),
    };
    calls.push(recorded);
    recorded.signal?.throwIfAborted();
    return await handler(recorded);
  };
  const restore = (): void => {
    globalThis.fetch = original;
  };
  return { calls, restore, [Symbol.dispose]: restore };
}

/** A log sink that keeps parsed lines in memory. */
export function memorySink(): {
  sink: LogSink;
  lines: Array<{ level: LogLevel; entry: Record<string, unknown> }>;
} {
  const lines: Array<{ level: LogLevel; entry: Record<string, unknown> }> = [];
  return { sink: (level, line) => lines.push({ level, entry: JSON.parse(line) }), lines };
}
