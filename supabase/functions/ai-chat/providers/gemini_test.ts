import {
  assert,
  assertEquals,
  assertFalse,
  assertInstanceOf,
  assertRejects,
} from "jsr:@std/assert@1.0.19";
import { mockFetch, streamFromChunks } from "../../_shared/testing.ts";
import { ProviderError, type ProviderEvent, type StreamParams } from "../types.ts";
import {
  buildGeminiRequest,
  createGeminiProvider,
  geminiStreamUrl,
  geminiUsage,
  mapGeminiFinishReason,
} from "./gemini.ts";

const KEY = "test-gemini-key";
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

const chunk = (value: unknown): string => `data: ${JSON.stringify(value)}\n\n`;
const textChunk = (
  texts: Array<string | { text: string; thought?: boolean }>,
  extra = {},
) =>
  chunk({
    candidates: [{
      content: {
        role: "model",
        parts: texts.map((t) => typeof t === "string" ? { text: t } : t),
      },
      ...extra,
    }],
  });

function sse(chunks: string[], status = 200): Response {
  return new Response(streamFromChunks(chunks), {
    status,
    headers: { "content-type": "text/event-stream" },
  });
}

async function run(
  chunks: string[],
  signal = new AbortController().signal,
): Promise<ProviderEvent[]> {
  using _fetch = mockFetch(() => sse(chunks));
  const provider = createGeminiProvider({
    apiKey: KEY,
    model: "gemini-3.8-flash",
  });
  const events: ProviderEvent[] = [];
  for await (const event of provider.streamText(params, signal)) {
    events.push(event);
  }
  return events;
}

const texts = (events: ProviderEvent[]): string =>
  events.map((e) => e.type === "text" ? e.text : "").join("");

Deno.test("request: header key, alt=sse URL, camelCase body with thinkingConfig", async () => {
  using fetchMock = mockFetch(() => sse([textChunk(["ok"], { finishReason: "STOP" })]));
  const provider = createGeminiProvider({
    apiKey: KEY,
    model: "gemini-3.8-flash",
  });
  for await (
    const _ of provider.streamText(params, new AbortController().signal)
  ) {
    // drain
  }
  const call = fetchMock.calls[0];
  assertEquals(
    call.url,
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:streamGenerateContent?alt=sse",
  );
  assertFalse(call.url.includes(KEY), "the key never goes in the URL");
  assertEquals(call.method, "POST");
  assertEquals(call.headers.get("x-goog-api-key"), KEY);
  assertEquals(call.headers.get("content-type"), "application/json");
  assertEquals(JSON.parse(call.body), {
    systemInstruction: {
      parts: [{ text: "INSTRUCTIONS" }, { text: "CONTEXT" }],
    },
    contents: [
      { role: "user", parts: [{ text: "Hi" }] },
      { role: "model", parts: [{ text: "Hello" }] },
      { role: "user", parts: [{ text: "Food total?" }] },
    ],
    generationConfig: {
      maxOutputTokens: 4096,
      thinkingConfig: { thinkingLevel: "LOW" },
    },
  });
  assert(call.signal !== null);
});

Deno.test("buildGeminiRequest never sends thinkingBudget or sampling params", () => {
  const body = JSON.stringify(buildGeminiRequest(params));
  for (const key of ["thinkingBudget", "temperature", "topP", "topK"]) {
    assertFalse(body.includes(key));
  }
});

Deno.test("geminiStreamUrl encodes the model name", () => {
  assertEquals(
    geminiStreamUrl("a/b", "https://example.test"),
    "https://example.test/v1beta/models/a%2Fb:streamGenerateContent?alt=sse",
  );
});

Deno.test("multi-chunk stream with usage and STOP", async () => {
  const events = await run([
    textChunk(["Hello"]),
    textChunk([", "]),
    chunk({
      candidates: [{
        content: { parts: [{ text: "world" }] },
        finishReason: "STOP",
      }],
      usageMetadata: {
        promptTokenCount: 11,
        candidatesTokenCount: 3,
        thoughtsTokenCount: 20,
      },
    }),
  ]);
  assertEquals(texts(events), "Hello, world");
  assertEquals(events.filter((e) => e.type === "usage"), [
    { type: "usage", usage: { inputTokens: 11, outputTokens: 23 } },
  ]);
  assertEquals(events.at(-1), { type: "stop", reason: "end" });
});

Deno.test("a chunk with only thought parts yields a payload-free progress event", async () => {
  const events = await run([
    chunk({ candidates: [{ content: { parts: [{ text: "HIDDEN", thought: true }] } }] }),
    textChunk(["Answer"], { finishReason: "STOP" }),
  ]);
  assertEquals(events[0], { type: "progress" });
  assertEquals(texts(events), "Answer");
  assertEquals(JSON.stringify(events).includes("HIDDEN"), false);
});

Deno.test("lines split across network chunks and CRLF endings are reassembled", async () => {
  const full = textChunk(["Split ", "text"], { finishReason: "STOP" }).replace(
    /\n/g,
    "\r\n",
  );
  const pieces = [
    full.slice(0, 7),
    full.slice(7, 30),
    full.slice(30, full.length - 3),
  ];
  pieces.push(full.slice(full.length - 3));
  const events = await run(pieces);
  assertEquals(texts(events), "Split text");
  assertEquals(events.at(-1), { type: "stop", reason: "end" });
});

Deno.test("a multi-byte character split across chunks survives", async () => {
  const bytes = new TextEncoder().encode(
    textChunk(["₹500 spent"], { finishReason: "STOP" }),
  );
  const cut = bytes.indexOf(0xe2) + 1; // inside the 3-byte ₹
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(bytes.slice(0, cut));
      controller.enqueue(bytes.slice(cut));
      controller.close();
    },
  });
  using _fetch = mockFetch(() => new Response(body, { status: 200 }));
  const provider = createGeminiProvider({
    apiKey: KEY,
    model: "gemini-3.8-flash",
  });
  const events: ProviderEvent[] = [];
  for await (
    const e of provider.streamText(params, new AbortController().signal)
  ) events.push(e);
  assertEquals(texts(events), "₹500 spent");
});

Deno.test("thought parts are skipped, including whole thought-only chunks", async () => {
  const events = await run([
    textChunk([{ text: "planning the answer", thought: true }]),
    textChunk([{ text: "more thinking", thought: true }, "Visible"]),
    textChunk([" answer"], { finishReason: "STOP" }),
  ]);
  assertEquals(texts(events), "Visible answer");
  assertFalse(JSON.stringify(events).includes("thinking"));
});

Deno.test("MAX_TOKENS ends with max_tokens", async () => {
  const events = await run([
    textChunk(["cut"], { finishReason: "MAX_TOKENS" }),
  ]);
  assertEquals(events.at(-1), { type: "stop", reason: "max_tokens" });
});

Deno.test("promptFeedback.blockReason ends with blocked and no text", async () => {
  const events = await run([
    chunk({ promptFeedback: { blockReason: "PROHIBITED_CONTENT" } }),
  ]);
  assertEquals(events, [{ type: "stop", reason: "blocked" }]);
});

Deno.test("safety finish reasons map to blocked", () => {
  for (
    const reason of [
      "SAFETY",
      "RECITATION",
      "BLOCKLIST",
      "PROHIBITED_CONTENT",
      "SPII",
      "LANGUAGE",
      "OTHER",
    ]
  ) {
    assertEquals(mapGeminiFinishReason(reason), "blocked", reason);
  }
  assertEquals(mapGeminiFinishReason("STOP"), "end");
  assertEquals(mapGeminiFinishReason("MAX_TOKENS"), "max_tokens");
  assertEquals(mapGeminiFinishReason(undefined), undefined);
  assertEquals(mapGeminiFinishReason("FINISH_REASON_UNSPECIFIED"), undefined);
  assertEquals(mapGeminiFinishReason("MALFORMED_RESPONSE"), "error");
});

Deno.test("SAFETY after text yields the text then stop blocked", async () => {
  const events = await run([
    textChunk(["Partial"]),
    textChunk([], { finishReason: "SAFETY" }),
  ]);
  assertEquals(texts(events), "Partial");
  assertEquals(events.at(-1), { type: "stop", reason: "blocked" });
});

Deno.test("HTTP errors map to ProviderError kinds without reading the body", async () => {
  const cases: Array<[number, string]> = [
    [429, "rate_limited"],
    [402, "unavailable"],
    [500, "unavailable"],
    [503, "unavailable"],
    [400, "bad_request"],
    [404, "bad_request"],
    [401, "auth"],
    [403, "auth"],
  ];
  for (const [status, kind] of cases) {
    using _fetch = mockFetch(() =>
      new Response(JSON.stringify({ error: { message: "secret echo" } }), {
        status,
      })
    );
    const provider = createGeminiProvider({
      apiKey: KEY,
      model: "gemini-3.8-flash",
    });
    const error = await assertRejects(async () => {
      for await (
        const _ of provider.streamText(params, new AbortController().signal)
      ) {
        // drain
      }
    });
    assertInstanceOf(error, ProviderError);
    assertEquals(error.kind, kind, String(status));
    assertEquals(error.status, status);
    assertFalse(error.message.includes("secret echo"));
  }
});

Deno.test("network failure is unavailable", async () => {
  using _fetch = mockFetch(() => Promise.reject(new TypeError("dns")));
  const provider = createGeminiProvider({
    apiKey: KEY,
    model: "gemini-3.8-flash",
  });
  const error = await assertRejects(async () => {
    for await (
      const _ of provider.streamText(params, new AbortController().signal)
    ) {
      // drain
    }
  });
  assertInstanceOf(error, ProviderError);
  assertEquals(error.kind, "unavailable");
});

Deno.test("in-stream error objects, bad JSON and missing finish reason throw", async () => {
  const cases: Array<[string[], string]> = [
    [
      [chunk({ error: { code: 429, status: "RESOURCE_EXHAUSTED" } })],
      "rate_limited",
    ],
    [[chunk({ error: { status: "RESOURCE_EXHAUSTED" } })], "rate_limited"],
    // Prepaid credits depleted: not a rate limit, even with RESOURCE_EXHAUSTED.
    [
      [chunk({ error: { code: 402, status: "RESOURCE_EXHAUSTED" } })],
      "unavailable",
    ],
    [[chunk({ error: { code: 500, status: "INTERNAL" } })], "unavailable"],
    [["data: {not json\n\n"], "unavailable"],
    [[textChunk(["no finish"])], "unavailable"],
    [
      [textChunk(["odd"], { finishReason: "MALFORMED_RESPONSE" })],
      "unavailable",
    ],
  ];
  for (const [chunks, kind] of cases) {
    const error = await assertRejects(() => run(chunks));
    assertInstanceOf(error, ProviderError);
    assertEquals(error.kind, kind);
  }
});

Deno.test("aborting the signal stops the stream and cancels the body", async () => {
  let cancelled = false;
  const encoder = new TextEncoder();
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(encoder.encode(textChunk(["first"])));
    },
    cancel() {
      cancelled = true;
    },
  });
  using _fetch = mockFetch(() => new Response(body, { status: 200 }));
  const provider = createGeminiProvider({
    apiKey: KEY,
    model: "gemini-3.8-flash",
  });
  const controller = new AbortController();
  const seen: ProviderEvent[] = [];
  await assertRejects(async () => {
    for await (const event of provider.streamText(params, controller.signal)) {
      seen.push(event);
      controller.abort();
    }
  });
  assertEquals(seen, [{ type: "text", text: "first" }]);
  assert(cancelled, "the upstream body is cancelled");
});

Deno.test("geminiUsage", () => {
  assertEquals(geminiUsage(undefined), undefined);
  assertEquals(geminiUsage({}), undefined);
  assertEquals(geminiUsage({ promptTokenCount: 5 }), {
    inputTokens: 5,
    outputTokens: undefined,
  });
  assertEquals(
    geminiUsage({ candidatesTokenCount: 2, thoughtsTokenCount: 3 }),
    {
      inputTokens: undefined,
      outputTokens: 5,
    },
  );
});
