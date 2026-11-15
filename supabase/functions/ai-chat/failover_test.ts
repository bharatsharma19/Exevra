import { assert, assertEquals } from "jsr:@std/assert@1.0.19";
import { fakeTimers } from "../_shared/testing.ts";
import { type FailoverOutcome, type FailoverSink, runWithFailover } from "./failover.ts";
import {
  answer,
  deferred,
  failing,
  failingAfter,
  fakeProvider,
  flush,
  hanging,
} from "./testing.ts";
import { type ChatProvider, ProviderError, type StreamParams } from "./types.ts";

const params: StreamParams = {
  instructions: "i",
  context: "c",
  turns: [{ role: "user", content: "q" }],
  maxOutputTokens: 4096,
};

interface TestSink extends FailoverSink {
  started: string[];
  text_: string[];
  discards: number;
}

/** A sink that delivers every chunk (like the handler without the filter). */
function plainSink(): TestSink {
  const sink: TestSink = {
    started: [],
    text_: [],
    discards: 0,
    text(provider, _model, text) {
      if (sink.started.length === 0 || sink.started.at(-1) !== provider) {
        sink.started.push(provider);
      }
      sink.text_.push(text);
      return true;
    },
    end: () => false,
    discard() {
      sink.discards++;
    },
  };
  return sink;
}

function run(
  providers: readonly ChatProvider[],
  signal = new AbortController().signal,
  timers = fakeTimers(),
  sink: FailoverSink = plainSink(),
) {
  const outcome = runWithFailover({
    providers,
    params,
    signal,
    clock: timers.clock,
    timers,
    sink,
  });
  const test = sink as TestSink;
  return { outcome, started: test.started, text: test.text_, timers };
}

Deno.test("text goes to the sink; empty chunks are skipped", async () => {
  const r = run([fakeProvider("claude", answer(["a", "", "b"]))]);
  const outcome = await r.outcome;
  assertEquals(r.started, ["claude"]);
  assertEquals(r.text, ["a", "b"]);
  assertEquals(outcome.status, "done");
});

Deno.test("ttft is measured with the injected clock", async () => {
  const timers = fakeTimers();
  const claude = fakeProvider("claude", async function* () {
    await Promise.resolve();
    timers.clock.advance(850);
    yield { type: "text", text: "hi" };
    yield { type: "stop", reason: "end" };
  });
  const outcome = await run([claude], undefined, timers).outcome;
  assert(outcome.status === "done");
  assertEquals(outcome.ttftMs, 850);
});

Deno.test("a provider that ignores abort still times out and fails over", async () => {
  const started = deferred();
  // Never yields and never looks at the signal.
  const stuck = fakeProvider("claude", async function* () {
    started.resolve();
    await new Promise(() => {});
    yield { type: "text", text: "never" };
  });
  const r = run([stuck, fakeProvider("gemini", answer(["ok"]))]);
  await started.promise;
  r.timers.tick(12_000);
  const outcome = await r.outcome;
  assertEquals(outcome.status, "done");
  assertEquals(r.started, ["gemini"]);
  assert(stuck.calls[0].signal.aborted);
});

Deno.test("a provider whose streamText throws synchronously fails over", async () => {
  const broken: ChatProvider = {
    name: "claude",
    model: "m",
    streamText() {
      throw new ProviderError("auth", { status: 401 });
    },
  };
  const r = run([broken, fakeProvider("gemini", answer(["ok"]))]);
  const outcome = await r.outcome;
  assert(outcome.status === "done");
  assertEquals(outcome.provider, "gemini");
  assertEquals(outcome.attempts, [{
    provider: "claude",
    model: "m",
    failure: "auth",
    status: 401,
    usage: {},
  }]);
});

Deno.test("an already-aborted client signal starts nothing", async () => {
  const controller = new AbortController();
  controller.abort();
  const claude = fakeProvider("claude", answer(["x"]));
  const outcome = await run([claude], controller.signal).outcome;
  assertEquals(outcome.status, "aborted");
  assertEquals(claude.calls.length, 0);
});

Deno.test("abort while waiting for the first token does not fail over", async () => {
  const controller = new AbortController();
  const started = deferred();
  const claude = fakeProvider("claude", hanging(() => started.resolve()));
  const gemini = fakeProvider("gemini", answer(["no"]));
  const r = run([claude, gemini], controller.signal);
  await started.promise;
  controller.abort();
  const outcome: FailoverOutcome = await r.outcome;
  assertEquals(outcome.status, "aborted");
  assertEquals(gemini.calls.length, 0);
  assert(claude.calls[0].signal.aborted);
});

Deno.test("the final code is unavailable when only some failures are 429", async () => {
  const outcome = await run([
    fakeProvider(
      "claude",
      failing(new ProviderError("rate_limited", { status: 429 })),
    ),
    fakeProvider("gemini", answer([], "end")),
  ]).outcome;
  assert(outcome.status === "failed");
  assertEquals(outcome.code, "unavailable");
  assertEquals(outcome.attempts.map((a) => a.failure), [
    "rate_limited",
    "empty",
  ]);
});

Deno.test("a single rate-limited provider gives rate_limited", async () => {
  const outcome = await run([
    fakeProvider(
      "gemini",
      failing(new ProviderError("rate_limited", { status: 429 })),
    ),
  ]).outcome;
  assert(outcome.status === "failed");
  assertEquals(outcome.code, "rate_limited");
});

Deno.test("no timers are left behind after completion", async () => {
  const timers = fakeTimers();
  await run([fakeProvider("claude", answer(["a", "b"]))], undefined, timers)
    .outcome;
  await flush();
  assertEquals(timers.pending(), 0);
});

// ---- No-splice guarantee ---------------------------------------------------------------------

Deno.test("a sink that throws on the first text commits: the next provider is never called", async () => {
  const sink: FailoverSink = {
    text: () => {
      throw new Error("writer broke");
    },
    end: () => false,
    discard: () => {},
  };
  const claude = fakeProvider("claude", answer(["Hello"]));
  const gemini = fakeProvider("gemini", answer(["SPLICED"]));
  const outcome = await run([claude, gemini], undefined, undefined, sink)
    .outcome;
  assertEquals(gemini.calls.length, 0);
  assert(outcome.status === "interrupted");
  assertEquals(outcome.provider, "claude");
  assertEquals(outcome.reason, "error");
  assert(claude.calls[0].signal.aborted, "the provider call is released");
});

Deno.test("a sink that throws at the end of the answer does not fail over", async () => {
  let delivered = 0;
  const sink: FailoverSink = {
    text: () => {
      delivered++;
      return true;
    },
    end: () => {
      throw new Error("writer broke");
    },
    discard: () => {},
  };
  const gemini = fakeProvider("gemini", answer(["SPLICED"]));
  const outcome = await run(
    [fakeProvider("claude", answer(["Hi"])), gemini],
    undefined,
    undefined,
    sink,
  ).outcome;
  assertEquals(delivered, 1);
  assertEquals(gemini.calls.length, 0);
  assertEquals(outcome.status, "interrupted");
});

Deno.test("a sink that throws before writing anything still counts as delivered", async () => {
  // Even an empty `end` flush that throws commits: the bytes may be on the wire.
  const sink: FailoverSink = {
    text: () => false,
    end: () => {
      throw new Error("writer broke");
    },
    discard: () => {},
  };
  const gemini = fakeProvider("gemini", answer(["SPLICED"]));
  const outcome = await run(
    [fakeProvider("claude", answer(["held back"])), gemini],
    undefined,
    undefined,
    sink,
  ).outcome;
  assertEquals(gemini.calls.length, 0);
  assertEquals(outcome.status, "interrupted");
});

Deno.test("every kind of failure after delivery ends the answer without another provider", async () => {
  const cases: Array<
    [
      string,
      () => ChatProvider,
      (timers: ReturnType<typeof fakeTimers>) => void,
    ]
  > = [
    [
      "provider error",
      () =>
        fakeProvider(
          "claude",
          failingAfter(["Hi"], new ProviderError("unavailable")),
        ),
      () => {},
    ],
    [
      "non-provider error",
      () => fakeProvider("claude", failingAfter(["Hi"], new TypeError("bug"))),
      () => {},
    ],
    [
      "stream ends without stop",
      () =>
        fakeProvider("claude", async function* () {
          yield { type: "text", text: "Hi" };
        }),
      () => {},
    ],
    [
      "a normal end after text",
      () => fakeProvider("claude", answer(["Hi"], "end")),
      () => {},
    ],
  ];
  for (const [label, make] of cases) {
    const gemini = fakeProvider("gemini", answer(["SPLICED"]));
    const r = run([make(), gemini]);
    const outcome = await r.outcome;
    assertEquals(gemini.calls.length, 0, label);
    assertEquals(r.text, ["Hi"], label);
    assert(
      outcome.status === "interrupted" || outcome.status === "done",
      label,
    );
  }
});

Deno.test("client disconnect after delivery is aborted with the provider; nothing else runs", async () => {
  const controller = new AbortController();
  const started = deferred();
  const claude = fakeProvider(
    "claude",
    hanging(() => started.resolve(), [{ type: "text", text: "Typing" }]),
  );
  const gemini = fakeProvider("gemini", answer(["SPLICED"]));
  const r = run([claude, gemini], controller.signal);
  await started.promise;
  await flush();
  controller.abort();
  const outcome = await r.outcome;
  assertEquals(outcome, {
    status: "aborted",
    provider: "claude",
    model: "claude-test-model",
    usage: {},
  });
  assertEquals(gemini.calls.length, 0);
});

Deno.test("text the sink held back (nothing delivered) still allows failover, and is discarded", async () => {
  const held: string[] = [];
  let discards = 0;
  const sink: FailoverSink = {
    text: (provider, _m, text) => {
      if (provider === "claude") {
        held.push(text);
        return false;
      }
      return true;
    },
    end: () => false,
    discard: () => {
      discards++;
    },
  };
  const claude = fakeProvider(
    "claude",
    failingAfter(["![x](https://e"], new ProviderError("unavailable")),
  );
  const gemini = fakeProvider("gemini", answer(["ok"]));
  const outcome = await run([claude, gemini], undefined, undefined, sink)
    .outcome;
  assert(outcome.status === "done");
  assertEquals(outcome.provider, "gemini");
  assertEquals(held, ["![x](https://e"]);
  assertEquals(discards, 1);
  assertEquals(outcome.attempts.map((a) => a.failure), ["unavailable"]);
});

Deno.test("an answer whose text was all removed by the sink is empty and fails over", async () => {
  const sink: FailoverSink = {
    text: (provider) => provider === "gemini",
    end: () => false,
    discard: () => {},
  };
  const outcome = await run(
    [
      fakeProvider("claude", answer(["![](https://e/p)"])),
      fakeProvider("gemini", answer(["ok"])),
    ],
    undefined,
    undefined,
    sink,
  ).outcome;
  assert(outcome.status === "done");
  assertEquals(outcome.provider, "gemini");
  assertEquals(outcome.attempts.map((a) => a.failure), ["empty"]);
});

Deno.test("refusal: before delivery -> declined; after delivery -> declined with afterText", async () => {
  const before = await run([
    fakeProvider("claude", answer([], "refusal")),
    fakeProvider("gemini", answer(["no"])),
  ]).outcome;
  assert(before.status === "declined");
  assertEquals(before.afterText, false);

  const gemini = fakeProvider("gemini", answer(["no"]));
  const after = await run([
    fakeProvider("claude", answer(["Sure, "], "refusal")),
    gemini,
  ]).outcome;
  assert(after.status === "declined");
  assertEquals(after.afterText, true);
  assertEquals(gemini.calls.length, 0);
});
