import {
  assert,
  assertEquals,
  assertFalse,
  assertInstanceOf,
  assertRejects,
} from "jsr:@std/assert@1.0.19";
import Anthropic from "npm:@anthropic-ai/sdk@1.8.0";
import { mockFetch, streamFromChunks } from "../../_shared/testing.ts";
import { ProviderError, type ProviderEvent, type StreamParams } from "../types.ts";
import {
  buildClaudeRequest,
  CLAUDE_SONNET_MODEL,
  type ClaudeStreamEventLike,
  createAnthropicClient,
  createClaudeProvider,
  mapClaudeError,
  mapClaudeStopReason,
  sdkStreamOpener,
  SERVER_SIDE_FALLBACK_BETA,
} from "./claude.ts";

/**
 * The SDK reads optional variables such as ANTHROPIC_CUSTOM_HEADERS when a client is built. Tests
 * run without env permission, so the client is built against an empty `process.env`.
 */
function testClient(): Anthropic {
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, "process");
  Object.defineProperty(globalThis, "process", {
    value: { env: {} },
    configurable: true,
  });
  try {
    return createAnthropicClient("test-anthropic-key", { maxRetries: 0 });
  } finally {
    if (descriptor) Object.defineProperty(globalThis, "process", descriptor);
    else delete (globalThis as { process?: unknown }).process;
  }
}

const params: StreamParams = {
  instructions: "INSTRUCTIONS",
  context: "CONTEXT",
  turns: [
    { role: "user", content: "Hi" },
    { role: "assistant", content: "Hello" },
    { role: "user", content: "Food total?" },
  ],
  maxOutputTokens: 4096,
};

async function collect(
  iterable: AsyncIterable<ProviderEvent>,
): Promise<ProviderEvent[]> {
  const events: ProviderEvent[] = [];
  for await (const event of iterable) events.push(event);
  return events;
}

function fakeOpen(events: ClaudeStreamEventLike[], error?: unknown) {
  const bodies: unknown[] = [];
  const open = async function* (
    body: unknown,
  ): AsyncGenerator<ClaudeStreamEventLike> {
    bodies.push(body);
    for (const event of events) yield event;
    if (error !== undefined) throw error;
  };
  return { open, bodies };
}

const textDelta = (text: string): ClaudeStreamEventLike => ({
  type: "content_block_delta",
  delta: { type: "text_delta", text },
});

Deno.test("request body: system blocks, effort low, 4096 tokens, no sampling params", () => {
  const body = buildClaudeRequest("claude-haiku-5-5", params);
  assertEquals(body, {
    model: "claude-haiku-5-5",
    max_tokens: 4096,
    system: [
      {
        type: "text",
        text: "INSTRUCTIONS",
        cache_control: { type: "ephemeral" },
      },
      { type: "text", text: "CONTEXT" },
    ],
    messages: [
      { role: "user", content: "Hi" },
      { role: "assistant", content: "Hello" },
      { role: "user", content: "Food total?" },
    ],
    output_config: { effort: "low" },
  });
  const raw = body as unknown as Record<string, unknown>;
  for (const key of ["temperature", "top_p", "top_k", "thinking"]) {
    assertFalse(key in raw);
  }
});

Deno.test("fake SDK stream: only text_delta is yielded; usage and stop are reported", async () => {
  const { open } = fakeOpen([
    {
      type: "message_start",
      message: {
        usage: {
          input_tokens: 100,
          cache_read_input_tokens: 20,
          cache_creation_input_tokens: 5,
        },
      },
    },
    { type: "content_block_start" },
    { type: "content_block_delta", delta: { type: "thinking_delta" } },
    { type: "content_block_delta", delta: { type: "signature_delta" } },
    { type: "content_block_stop" },
    textDelta("Hello"),
    textDelta(""),
    textDelta(" world"),
    {
      type: "message_delta",
      delta: { stop_reason: "end_turn" },
      usage: { output_tokens: 42 },
    },
    { type: "message_stop" },
  ]);
  const provider = createClaudeProvider({ model: "claude-haiku-5-5", open });
  const events = await collect(
    provider.streamText(params, new AbortController().signal),
  );
  // Ignored upstream events (thinking, block boundaries, empty text) become payload-free
  // `progress` events, which only keep the idle timer from firing.
  assertEquals(events, [
    { type: "usage", usage: { inputTokens: 125 } },
    { type: "progress" },
    { type: "progress" },
    { type: "progress" },
    { type: "progress" },
    { type: "text", text: "Hello" },
    { type: "progress" },
    { type: "text", text: " world" },
    { type: "usage", usage: { inputTokens: 125, outputTokens: 42 } },
    { type: "progress" },
    { type: "stop", reason: "end" },
  ]);
  assertFalse(JSON.stringify(events).includes("thinking"));
});

Deno.test("stop reasons map to end / max_tokens / refusal", () => {
  assertEquals(mapClaudeStopReason("end_turn"), "end");
  assertEquals(mapClaudeStopReason("stop_sequence"), "end");
  assertEquals(mapClaudeStopReason("max_tokens"), "max_tokens");
  assertEquals(
    mapClaudeStopReason("model_context_window_exceeded"),
    "max_tokens",
  );
  assertEquals(mapClaudeStopReason("refusal"), "refusal");
});

Deno.test("refusal with null stop_details yields stop refusal", async () => {
  const { open } = fakeOpen([
    {
      type: "message_delta",
      delta: { stop_reason: "refusal" },
      usage: { output_tokens: 0 },
    },
  ]);
  const provider = createClaudeProvider({ model: "claude-haiku-5-5", open });
  const events = await collect(
    provider.streamText(params, new AbortController().signal),
  );
  assertEquals(events.at(-1), { type: "stop", reason: "refusal" });
});

Deno.test("a stream without stop_reason is a ProviderError", async () => {
  const { open } = fakeOpen([textDelta("cut")]);
  const provider = createClaudeProvider({ model: "claude-haiku-5-5", open });
  const error = await assertRejects(() =>
    collect(provider.streamText(params, new AbortController().signal))
  );
  assertInstanceOf(error, ProviderError);
  assertEquals(error.kind, "unavailable");
});

Deno.test("SDK errors map to ProviderError kinds, most specific first", () => {
  const headers = new Headers();
  const cases: Array<[unknown, string, number | undefined]> = [
    [
      new Anthropic.RateLimitError(429, undefined, "x", headers),
      "rate_limited",
      429,
    ],
    [
      new Anthropic.APIConnectionError({ message: "x" }),
      "unavailable",
      undefined,
    ],
    [new Anthropic.APIConnectionTimeoutError(), "unavailable", undefined],
    [
      new Anthropic.InternalServerError(500, undefined, "x", headers),
      "unavailable",
      500,
    ],
    [
      new Anthropic.InternalServerError(529, undefined, "x", headers),
      "unavailable",
      529,
    ],
    [
      new Anthropic.AuthenticationError(401, undefined, "x", headers),
      "auth",
      401,
    ],
    [
      new Anthropic.PermissionDeniedError(403, undefined, "x", headers),
      "auth",
      403,
    ],
    [
      new Anthropic.NotFoundError(404, undefined, "x", headers),
      "bad_request",
      404,
    ],
    [
      new Anthropic.BadRequestError(400, undefined, "x", headers),
      "bad_request",
      400,
    ],
    [new Anthropic.APIError(418, undefined, "x", headers), "unavailable", 418],
    [new Anthropic.APIUserAbortError(), "unavailable", undefined],
    [new TypeError("x"), "unavailable", undefined],
  ];
  for (const [error, kind, status] of cases) {
    const mapped = mapClaudeError(error);
    assertEquals(mapped.kind, kind, String(error));
    assertEquals(mapped.status, status, String(error));
  }
});

Deno.test("errors thrown mid-stream surface as ProviderError after earlier text", async () => {
  const { open } = fakeOpen(
    [textDelta("Hi")],
    new Anthropic.InternalServerError(
      529,
      undefined,
      "overloaded",
      new Headers(),
    ),
  );
  const provider = createClaudeProvider({ model: "claude-haiku-5-5", open });
  const seen: ProviderEvent[] = [];
  const error = await assertRejects(async () => {
    for await (
      const event of provider.streamText(params, new AbortController().signal)
    ) {
      seen.push(event);
    }
  });
  assertEquals(seen, [{ type: "text", text: "Hi" }]);
  assertInstanceOf(error, ProviderError);
  assertEquals(error.status, 529);
});

// ---- Real SDK over a mocked fetch ------------------------------------------------------------

function anthropicSse(events: Array<Record<string, unknown>>): string[] {
  return events.map((e) => `event: ${e.type}\ndata: ${JSON.stringify(e)}\n\n`);
}

const MESSAGE = {
  id: "msg_test",
  type: "message",
  role: "assistant",
  content: [],
  model: "claude-haiku-5-5",
  stop_reason: null,
  stop_sequence: null,
  usage: { input_tokens: 30, output_tokens: 1 },
};

function successBody(): string[] {
  return anthropicSse([
    { type: "message_start", message: MESSAGE },
    {
      type: "content_block_start",
      index: 0,
      content_block: { type: "thinking", thinking: "", signature: "" },
    },
    {
      type: "content_block_delta",
      index: 0,
      delta: { type: "thinking_delta", thinking: "HIDDEN" },
    },
    {
      type: "content_block_delta",
      index: 0,
      delta: { type: "signature_delta", signature: "s" },
    },
    { type: "content_block_stop", index: 0 },
    {
      type: "content_block_start",
      index: 1,
      content_block: { type: "text", text: "" },
    },
    {
      type: "content_block_delta",
      index: 1,
      delta: { type: "text_delta", text: "Real " },
    },
    {
      type: "content_block_delta",
      index: 1,
      delta: { type: "text_delta", text: "SDK" },
    },
    { type: "content_block_stop", index: 1 },
    {
      type: "message_delta",
      delta: { stop_reason: "end_turn", stop_sequence: null },
      usage: { output_tokens: 12 },
    },
    { type: "message_stop" },
  ]);
}

Deno.test("real SDK (Haiku): plain endpoint, no beta header, thinking skipped", async () => {
  using fetchMock = mockFetch(() =>
    new Response(streamFromChunks(successBody()), {
      status: 200,
      headers: { "content-type": "text/event-stream" },
    })
  );
  const client = testClient();
  const provider = createClaudeProvider({
    model: "claude-haiku-5-5",
    open: sdkStreamOpener(client),
  });
  const events = await collect(
    provider.streamText(params, new AbortController().signal),
  );
  assertEquals(
    events.filter((e) => e.type === "text").map((e) => e.type === "text" ? e.text : ""),
    ["Real ", "SDK"],
  );
  assertEquals(events.at(-1), { type: "stop", reason: "end" });
  assertFalse(JSON.stringify(events).includes("HIDDEN"));

  assertEquals(fetchMock.calls.length, 1);
  const call = fetchMock.calls[0];
  assert(call.url.startsWith("https://api.anthropic.com/v1/messages"));
  assertEquals(call.headers.get("anthropic-beta"), null);
  const sent = JSON.parse(call.body);
  assertEquals(sent.model, "claude-haiku-5-5");
  assertEquals(sent.max_tokens, 4096);
  assertEquals(sent.stream, true);
  assertEquals(sent.output_config, { effort: "low" });
  assertFalse("fallbacks" in sent);
  assertFalse("temperature" in sent);
  assert(call.signal !== null);
});

Deno.test("real SDK (Sonnet): beta endpoint with server-side fallback", async () => {
  using fetchMock = mockFetch(() =>
    new Response(streamFromChunks(successBody()), {
      status: 200,
      headers: { "content-type": "text/event-stream" },
    })
  );
  const client = testClient();
  const provider = createClaudeProvider({
    model: CLAUDE_SONNET_MODEL,
    open: sdkStreamOpener(client),
  });
  await collect(provider.streamText(params, new AbortController().signal));
  const call = fetchMock.calls[0];
  assert(call.url.startsWith("https://api.anthropic.com/v1/messages"));
  assertEquals(call.headers.get("anthropic-beta"), SERVER_SIDE_FALLBACK_BETA);
  const sent = JSON.parse(call.body);
  assertEquals(sent.fallbacks, "default");
  assertFalse("betas" in sent);
});

Deno.test("real SDK: HTTP 429 and 529 become typed ProviderErrors", async () => {
  for (
    const [status, kind] of [[429, "rate_limited"], [
      529,
      "unavailable",
    ]] as const
  ) {
    using _fetch = mockFetch(() =>
      new Response(
        JSON.stringify({ type: "error", error: { type: "x", message: "x" } }),
        {
          status,
          headers: { "content-type": "application/json" },
        },
      )
    );
    const client = testClient();
    const provider = createClaudeProvider({
      model: "claude-haiku-5-5",
      open: sdkStreamOpener(client),
    });
    const error = await assertRejects(() =>
      collect(provider.streamText(params, new AbortController().signal))
    );
    assertInstanceOf(error, ProviderError);
    assertEquals(error.kind, kind);
    assertEquals(error.status, status);
  }
});

Deno.test("real SDK: a network failure is unavailable", async () => {
  using _fetch = mockFetch(() => Promise.reject(new TypeError("connection refused")));
  const client = testClient();
  const provider = createClaudeProvider({
    model: "claude-haiku-5-5",
    open: sdkStreamOpener(client),
  });
  const error = await assertRejects(() =>
    collect(provider.streamText(params, new AbortController().signal))
  );
  assertInstanceOf(error, ProviderError);
  assertEquals(error.kind, "unavailable");
});

Deno.test("SDK logging and tracing ignore ANTHROPIC_LOG and content-mode tracing variables", () => {
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, "process");
  Object.defineProperty(globalThis, "process", {
    value: {
      env: {
        ANTHROPIC_LOG: "debug",
        ANTHROPIC_OPEN_TELEMETRY_TRACES_CONTENT_MODE: "content",
      },
    },
    configurable: true,
  });
  let client: Anthropic;
  try {
    client = createAnthropicClient("test-anthropic-key");
  } finally {
    if (descriptor) Object.defineProperty(globalThis, "process", descriptor);
    else delete (globalThis as { process?: unknown }).process;
  }
  assertEquals(client.logLevel, "warn");
});

Deno.test("real SDK: the stream itself is never retried by the SDK (failover is the retry)", async () => {
  using fetchMock = mockFetch(() =>
    new Response(JSON.stringify({ type: "error", error: { type: "x", message: "x" } }), {
      status: 529,
      headers: { "content-type": "application/json", "retry-after": "0" },
    })
  );
  // A client that would retry twice if the stream did not override it.
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, "process");
  Object.defineProperty(globalThis, "process", { value: { env: {} }, configurable: true });
  let client: Anthropic;
  try {
    client = createAnthropicClient("test-anthropic-key", { maxRetries: 2 });
  } finally {
    if (descriptor) Object.defineProperty(globalThis, "process", descriptor);
    else delete (globalThis as { process?: unknown }).process;
  }
  for (const model of ["claude-haiku-5-5", CLAUDE_SONNET_MODEL]) {
    const provider = createClaudeProvider({ model, open: sdkStreamOpener(client) });
    const error = await assertRejects(() =>
      collect(provider.streamText(params, new AbortController().signal))
    );
    assertInstanceOf(error, ProviderError);
  }
  assertEquals(fetchMock.calls.length, 2, "one request per model, no retries");
});
