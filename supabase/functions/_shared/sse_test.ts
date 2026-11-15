import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1.0.19";
import {
  createSseStream,
  encodeSseComment,
  encodeSseEvent,
  parseSse,
  type SseMessage,
  SseOverflowError,
  sseResponse,
} from "./sse.ts";
import { fakeTimers, readAllText, streamFromChunks } from "./testing.ts";

async function collect(chunks: string[]): Promise<SseMessage[]> {
  const out: SseMessage[] = [];
  for await (const message of parseSse(streamFromChunks(chunks))) out.push(message);
  return out;
}

Deno.test("encodeSseEvent writes one data line even for multi-line text", () => {
  assertEquals(
    encodeSseEvent("delta", { text: "a\nb" }),
    'event: delta\ndata: {"text":"a\\nb"}\n\n',
  );
  assertEquals(encodeSseComment("ping"), ": ping\n\n");
  assertEquals(encodeSseComment("a\r\nb"), ": a b\n\n");
  assertThrows(() => encodeSseEvent("bad\nname", {}), TypeError);
});

Deno.test("createSseStream writes events, pings while open, and closes", async () => {
  const timers = fakeTimers();
  const { stream, writer } = createSseStream({ pingIntervalMs: 15_000, timers });
  writer.event("meta", { provider: "claude" });
  timers.tick(15_000);
  writer.event("done", { truncated: false });
  writer.close();
  timers.tick(60_000);
  assertEquals(writer.closed, true);
  assertEquals(writer.event("delta", { text: "late" }), false);
  assertEquals(timers.pending(), 0);
  assertEquals(
    await readAllText(stream),
    'event: meta\ndata: {"provider":"claude"}\n\n: ping\n\nevent: done\ndata: {"truncated":false}\n\n',
  );
});

Deno.test("createSseStream reports client disconnects once", async () => {
  const timers = fakeTimers();
  const reasons: unknown[] = [];
  const { stream, writer } = createSseStream({ timers, onCancel: (r) => reasons.push(r) });
  await stream.cancel("gone");
  assertEquals(reasons, ["gone"]);
  assertEquals(writer.closed, true);
  assertEquals(writer.comment("ping"), false);
  assertEquals(timers.pending(), 0);
  writer.close();
});

Deno.test("sseResponse sets streaming headers", () => {
  const res = sseResponse(new ReadableStream(), { "x-request-id": "r1" });
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("content-type"), "text/event-stream; charset=utf-8");
  assertEquals(res.headers.get("cache-control"), "no-cache, no-store, no-transform");
  assertEquals(res.headers.get("x-request-id"), "r1");
});

Deno.test("parseSse handles fields, comments and multi-line data", async () => {
  const messages = await collect([
    ": hello\n",
    'event: delta\ndata: {"a":1}\n\n',
    "data: line1\ndata:line2\nid: 7\n\n",
    "retry: 100\nunknown: x\n\n",
  ]);
  assertEquals(messages, [
    { event: "delta", data: '{"a":1}' },
    { event: "message", data: "line1\nline2", id: "7" },
  ]);
});

Deno.test("parseSse handles CRLF split across chunks and multibyte characters", async () => {
  const bytes = new TextEncoder().encode("data: héllo €\r\n\r\ndata: two\r");
  const parts = [bytes.slice(0, 9), bytes.slice(9, 15), bytes.slice(15, 16), bytes.slice(16)];
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      for (const part of parts) controller.enqueue(part);
      controller.enqueue(new TextEncoder().encode("\n\r\n"));
      controller.close();
    },
  });
  const out: SseMessage[] = [];
  for await (const message of parseSse(body)) out.push(message);
  assertEquals(out, [
    { event: "message", data: "héllo €" },
    { event: "message", data: "two" },
  ]);
});

Deno.test("parseSse treats a lone CR as a line break", async () => {
  assertEquals(await collect(["data: a\r\rdata: b\r", "\r"]), [
    { event: "message", data: "a" },
    { event: "message", data: "b" },
  ]);
});

Deno.test("parseSse dispatches a final event without a trailing blank line", async () => {
  assertEquals(await collect(['data: {"done":true}']), [
    { event: "message", data: '{"done":true}' },
  ]);
  assertEquals(await collect(["data: x\n"]), [{ event: "message", data: "x" }]);
});

Deno.test("parseSse cancels the body when the consumer stops early", async () => {
  let cancelled = false;
  const body = new ReadableStream<Uint8Array>({
    pull(controller) {
      controller.enqueue(new TextEncoder().encode("data: x\n\n"));
    },
    cancel() {
      cancelled = true;
    },
  });
  for await (const _ of parseSse(body)) break;
  assertEquals(cancelled, true);
});

Deno.test("parseSse rejects on abort and cancels the body", async () => {
  let cancelled = false;
  const controller = new AbortController();
  const body = new ReadableStream<Uint8Array>({
    cancel() {
      cancelled = true;
    },
  });
  const pending = (async () => {
    for await (const _ of parseSse(body, { signal: controller.signal })) {
      // never reached
    }
  })();
  controller.abort(new DOMException("client gone", "AbortError"));
  await assertRejects(() => pending, DOMException);
  assertEquals(cancelled, true);
});

Deno.test("parseSse limits buffered sizes", async () => {
  await assertRejects(
    async () => {
      for await (
        const _ of parseSse(streamFromChunks(["data: " + "x".repeat(100)]), {
          maxBufferChars: 50,
        })
      ) {
        // consume
      }
    },
    SseOverflowError,
  );
});
