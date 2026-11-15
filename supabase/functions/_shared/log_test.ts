import { assertEquals, assertMatch } from "jsr:@std/assert@1.0.19";
import {
  createLogger,
  errorName,
  isSensitiveLogKey,
  newRequestId,
  sanitizeLogFields,
} from "./log.ts";
import { fakeClock, memorySink } from "./testing.ts";

Deno.test("isSensitiveLogKey matches by name segment", () => {
  for (
    const key of ["user_id", "userId", "email", "access_token", "api_key", "content", "prompt"]
  ) {
    assertEquals(isSensitiveLogKey(key), true, key);
  }
  for (
    const key of ["request_id", "input_tokens", "output_tokens", "ttft_ms", "provider", "model"]
  ) {
    assertEquals(isSensitiveLogKey(key), false, key);
  }
});

Deno.test("sanitizeLogFields drops sensitive keys and redacts sensitive values", () => {
  assertEquals(
    sanitizeLogFields({
      request_id: "r1",
      user_id: "u1",
      status: "a@b.co",
      provider: "Bearer abc.def",
      model: "eyJhbGciOi.eyJzdWIiOi.sig",
      latency_ms: 12,
      bad: Number.NaN,
      ok: true,
      skip: undefined,
      code: "x\ny",
      long: "z".repeat(500),
    }),
    {
      request_id: "r1",
      status: "[redacted]",
      provider: "[redacted]",
      model: "[redacted]",
      latency_ms: 12,
      bad: null,
      ok: true,
      code: "x y",
      long: "z".repeat(200),
    },
  );
});

Deno.test("createLogger writes one JSON line with protected fields", () => {
  const { sink, lines } = memorySink();
  const log = createLogger("ai-chat", { sink, clock: fakeClock(0) });
  log.info({ request_id: "r1", fn: "spoofed", level: "spoofed", status: "ok" });
  log.error({ status: "error" });
  assertEquals(lines.length, 2);
  assertEquals(lines[0], {
    level: "info",
    entry: {
      request_id: "r1",
      status: "ok",
      ts: "1970-01-01T00:00:00.000Z",
      level: "info",
      fn: "ai-chat",
    },
  });
  assertEquals(lines[1].level, "error");
});

Deno.test("createLogger never throws when the sink fails", () => {
  const log = createLogger("x", {
    sink: () => {
      throw new Error("boom");
    },
  });
  log.warn({ status: "ok" });
});

Deno.test("errorName returns only the class name", () => {
  class ProviderError extends Error {
    constructor() {
      super("contains user text");
      this.name = "ProviderError";
    }
  }
  assertEquals(errorName(new ProviderError()), "ProviderError");
  assertEquals(errorName(new TypeError("x")), "TypeError");
  assertEquals(errorName("raw string"), "string");
  assertEquals(errorName(null), "null");
});

Deno.test("newRequestId returns a UUID", () => {
  assertMatch(
    newRequestId(),
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
  );
});
