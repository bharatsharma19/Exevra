import { assert, assertEquals } from "jsr:@std/assert@1.0.19";
import { fakeTimers } from "../_shared/testing.ts";
import { type FailoverOutcome, runWithFailover } from "./failover.ts";
import { answer, deferred, failing, fakeProvider, flush, hanging } from "./testing.ts";
import { type ChatProvider, ProviderError, type StreamParams } from "./types.ts";

const params: StreamParams = {
  instructions: "i",
  context: "c",
  turns: [{ role: "user", content: "q" }],
  maxOutputTokens: 4096,
};

function run(
  providers: readonly ChatProvider[],
  signal = new AbortController().signal,
  timers = fakeTimers(),
) {
  const started: string[] = [];
  const text: string[] = [];
  const outcome = runWithFailover({
    providers,
    params,
    signal,
    clock: timers.clock,
    timers,
    sink: { onStart: (p) => started.push(p), onText: (t) => text.push(t) },
  });
  return { outcome, started, text, timers };
}

Deno.test("onStart fires once, right before the first text", async () => {
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
