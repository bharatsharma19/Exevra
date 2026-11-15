/**
 * Provider failover. Providers are tried in order, but only until text has been delivered to the
 * client: after that the answer belongs to that provider, and any failure ends the stream. Text
 * from two providers is never mixed in one answer (see {@link Phase}).
 */
import type { Clock, TimerId, Timers } from "../_shared/clock.ts";
import {
  type ChatProvider,
  ProviderError,
  type ProviderErrorKind,
  type ProviderEvent,
  type ProviderName,
  type ProviderUsage,
  type StreamParams,
} from "./types.ts";

/** Time allowed from starting a provider call to its first text. */
export const FIRST_TOKEN_TIMEOUT_MS = 12_000;
/**
 * Time allowed between upstream events once text is flowing. Any event counts, including
 * thinking (`progress`) and usage, so a model thinking between text blocks is not cut off.
 */
export const STREAM_IDLE_TIMEOUT_MS = 30_000;

/**
 * Receives provider text on its way to the client. The sink (not the failover loop) decides what
 * is actually written, because the output filter may hold text back or remove it entirely.
 *
 * Contract: `text` and `end` return `true` when they wrote, or tried to write, anything to the
 * client. Throwing counts as a write attempt: the bytes may already be on the wire.
 */
export interface FailoverSink {
  /** Offers a chunk of answer text from `provider`. */
  text(provider: ProviderName, model: string, text: string): boolean;
  /** The provider finished normally: write whatever is still held back. */
  end(provider: ProviderName, model: string): boolean;
  /** Drops text held back for an attempt that is abandoned before it delivered anything. */
  discard(): void;
}

export interface FailoverOptions {
  providers: readonly ChatProvider[];
  params: StreamParams;
  /** Aborted when the client disconnects; aborts the active provider call. */
  signal: AbortSignal;
  sink: FailoverSink;
  clock: Clock;
  timers: Pick<Timers, "setTimeout" | "clearTimeout">;
  firstTokenTimeoutMs?: number;
  idleTimeoutMs?: number;
}

/** Why a provider attempt failed before delivering text. */
export type AttemptFailure = ProviderErrorKind | "timeout" | "empty";

/** One provider attempt that failed before any text. */
export interface FailedAttempt {
  provider: ProviderName;
  model: string;
  failure: AttemptFailure;
  status?: number;
  /** Tokens the attempt reported before failing (billed even though no text was used). */
  usage: ProviderUsage;
}

interface Served {
  provider: ProviderName;
  model: string;
  /** Time from this provider's start to the first text delivered to the client. */
  ttftMs?: number;
  /** Clock time of the first delivered text (for request-relative timings). */
  firstTokenAt?: number;
  usage: ProviderUsage;
  /** Earlier providers that failed before any text. */
  attempts: FailedAttempt[];
}

/** Result of {@link runWithFailover}. */
export type FailoverOutcome =
  /** The answer completed (`truncated` when it hit the output cap). */
  | (Served & { status: "done"; truncated: boolean })
  /**
   * The provider declined (Claude refusal or Gemini block). No failover. `afterText` is true when
   * text had already been delivered: the client must then discard that partial text.
   */
  | (Served & { status: "declined"; afterText: boolean })
  /** The provider failed after text was delivered. */
  | (Served & { status: "interrupted"; reason: "error" | "timeout" })
  /** Every provider failed before delivering any text. */
  | {
    status: "failed";
    code: "rate_limited" | "unavailable";
    attempts: FailedAttempt[];
  }
  /** The client went away. `provider` is set if text had been delivered. */
  | {
    status: "aborted";
    provider?: ProviderName;
    model?: string;
    usage: ProviderUsage;
  };

/**
 * The phase of one provider attempt. This is the whole no-splice guarantee:
 *
 * - `trying`: nothing has been delivered to the client. A failure (error, timeout, a stream that
 *   ends early or without visible text) abandons this attempt and the next provider is tried.
 * - `committed`: text was delivered, or a delivery was attempted (including a sink that threw).
 *   This provider owns the answer. No failure of any kind, from the provider, the sink or the
 *   client connection, can lead to another provider being called; it ends the answer instead.
 *
 * The only transition is `trying` -> `committed`, and only {@link AttemptResult} `next` (which
 * {@link attemptProvider} returns only while `trying`) lets the loop move on.
 */
type Phase = "trying" | "committed";

/** What one attempt tells the loop: move on (only possible while `trying`) or stop. */
type AttemptResult =
  | { kind: "next"; failed: FailedAttempt }
  | { kind: "final"; outcome: FailoverOutcome };

const TIMEOUT = Symbol("timeout");
const ABORTED = Symbol("aborted");
type Raced<T> = IteratorResult<T> | typeof TIMEOUT | typeof ABORTED;

/** Awaits the next event, a timeout or an abort, whichever comes first. */
async function nextOrTimeout<T>(
  iterator: AsyncIterator<T>,
  ms: number,
  signal: AbortSignal,
  timers: Pick<Timers, "setTimeout" | "clearTimeout">,
): Promise<Raced<T>> {
  if (signal.aborted) return ABORTED;
  let timer: TimerId | undefined;
  let onAbort: (() => void) | undefined;
  const next = iterator.next();
  // A provider rejecting after we stopped waiting must not become an unhandled rejection.
  next.catch(() => {});
  try {
    return await Promise.race<Raced<T>>([
      next,
      new Promise<typeof TIMEOUT>((resolve) => {
        timer = timers.setTimeout(() => resolve(TIMEOUT), Math.max(0, ms));
      }),
      new Promise<typeof ABORTED>((resolve) => {
        onAbort = () => resolve(ABORTED);
        signal.addEventListener("abort", onAbort, { once: true });
      }),
    ]);
  } finally {
    if (timer !== undefined) timers.clearTimeout(timer);
    if (onAbort) signal.removeEventListener("abort", onAbort);
  }
}

/** Ends a provider stream without waiting on it. */
function release<T>(
  iterator: AsyncIterator<T>,
  controller: AbortController,
): void {
  controller.abort();
  try {
    iterator.return?.()?.catch(() => {});
  } catch {
    // Ignore: the generator may already be running or finished.
  }
}

function mergeUsage(target: ProviderUsage, update: ProviderUsage): void {
  if (update.inputTokens !== undefined) target.inputTokens = update.inputTokens;
  if (update.outputTokens !== undefined) {
    target.outputTokens = update.outputTokens;
  }
}

interface AttemptContext {
  params: StreamParams;
  signal: AbortSignal;
  sink: FailoverSink;
  clock: Clock;
  timers: Pick<Timers, "setTimeout" | "clearTimeout">;
  firstTokenTimeout: number;
  idleTimeout: number;
  /** Earlier attempts (shared, for the outcome). */
  attempts: FailedAttempt[];
}

const errorKind = (err: unknown): ProviderErrorKind =>
  err instanceof ProviderError ? err.kind : "unavailable";
const errorStatus = (err: unknown): number | undefined =>
  err instanceof ProviderError ? err.status : undefined;

/** Runs one provider until it finishes, fails or the client goes away. */
async function attemptProvider(
  provider: ChatProvider,
  ctx: AttemptContext,
): Promise<AttemptResult> {
  const { params, signal, sink, clock, timers } = ctx;
  const controller = new AbortController();
  const onClientAbort = (): void => controller.abort(signal.reason);
  signal.addEventListener("abort", onClientAbort, { once: true });

  const started = clock.now();
  const usage: ProviderUsage = {};
  let phase: Phase = "trying";
  // Read through a function: `phase` changes inside closures, which TypeScript's narrowing of a
  // local `let` does not see.
  const committed = (): boolean => phase === "committed";
  /** Raw text arrived (even if the filter has not let any of it through yet). */
  let sawText = false;
  let ttftMs: number | undefined;
  let firstTokenAt: number | undefined;
  let iterator: AsyncIterator<ProviderEvent> | undefined;

  const served = (): Served => ({
    provider: provider.name,
    model: provider.model,
    ttftMs,
    firstTokenAt,
    usage,
    attempts: ctx.attempts,
  });
  const final = (outcome: FailoverOutcome): AttemptResult => ({
    kind: "final",
    outcome,
  });
  const aborted = (): AttemptResult =>
    final(
      committed()
        ? {
          status: "aborted",
          provider: provider.name,
          model: provider.model,
          usage,
        }
        : { status: "aborted", usage },
    );
  /** Every failure goes through here; only `trying` may move on to the next provider. */
  const failed = (failure: AttemptFailure, status?: number): AttemptResult => {
    if (signal.aborted) return aborted();
    if (committed()) {
      return final({
        ...served(),
        status: "interrupted",
        reason: failure === "timeout" ? "timeout" : "error",
      });
    }
    sink.discard();
    return {
      kind: "next",
      failed: {
        provider: provider.name,
        model: provider.model,
        failure,
        status,
        usage: { ...usage },
      },
    };
  };
  const commit = (): void => {
    if (committed()) return;
    phase = "committed";
    firstTokenAt = clock.now();
    ttftMs = firstTokenAt - started;
  };
  /** Calls the sink; commits when it wrote (or tried to). Returns false if the sink threw. */
  const deliver = (write: () => boolean): boolean => {
    try {
      if (write()) commit();
      return true;
    } catch {
      commit();
      return false;
    }
  };

  try {
    iterator = provider.streamText(params, controller.signal)
      [Symbol.asyncIterator]();
    while (true) {
      // Before any text the first-token deadline applies; once the provider has produced text
      // (delivered or held back by the filter) it has shown it is alive: the idle timer applies.
      const wait = sawText ? ctx.idleTimeout : started + ctx.firstTokenTimeout - clock.now();
      let result: Raced<ProviderEvent>;
      try {
        result = await nextOrTimeout(iterator, wait, signal, timers);
      } catch (err) {
        return failed(errorKind(err), errorStatus(err));
      }
      if (result === ABORTED) return aborted();
      if (result === TIMEOUT) return failed("timeout");
      // Adapters always end with `stop`; ending without one means the stream was cut off.
      if (result.done) return failed("unavailable");

      const event = result.value;
      switch (event.type) {
        case "progress":
          // Upstream is alive; the next wait restarts the idle timer (not the first-token one).
          continue;
        case "usage":
          mergeUsage(usage, event.usage);
          continue;
        case "text":
          if (event.text === "") continue;
          sawText = true;
          // A sink failure has committed the attempt, so `failed` ends the answer here.
          if (
            !deliver(() => sink.text(provider.name, provider.model, event.text))
          ) {
            return failed("unavailable");
          }
          continue;
        case "stop":
          if (event.reason === "refusal" || event.reason === "blocked") {
            if (!committed()) sink.discard();
            return final({
              ...served(),
              status: "declined",
              afterText: committed(),
            });
          }
          if (!deliver(() => sink.end(provider.name, provider.model))) {
            return failed("unavailable");
          }
          // Nothing visible was delivered (all output went to thinking, or the filter removed
          // it): this is a failure before any text, so the next provider may answer.
          if (!committed()) return failed("empty");
          return final({
            ...served(),
            status: "done",
            truncated: event.reason === "max_tokens",
          });
      }
    }
  } catch (err) {
    // streamText threw synchronously, or something unexpected happened. Still phase-checked.
    return failed(errorKind(err), errorStatus(err));
  } finally {
    signal.removeEventListener("abort", onClientAbort);
    if (iterator) release(iterator, controller);
    else controller.abort();
  }
}

/**
 * Streams an answer from the first provider that delivers text. A provider is abandoned only
 * while it has delivered nothing (see {@link Phase}); after that its outcome is final.
 */
export async function runWithFailover(
  options: FailoverOptions,
): Promise<FailoverOutcome> {
  const { providers, signal } = options;
  const ctx: AttemptContext = {
    params: options.params,
    signal,
    sink: options.sink,
    clock: options.clock,
    timers: options.timers,
    firstTokenTimeout: options.firstTokenTimeoutMs ?? FIRST_TOKEN_TIMEOUT_MS,
    idleTimeout: options.idleTimeoutMs ?? STREAM_IDLE_TIMEOUT_MS,
    attempts: [],
  };

  for (const provider of providers) {
    if (signal.aborted) return { status: "aborted", usage: {} };
    const result = await attemptProvider(provider, ctx);
    if (result.kind === "final") return result.outcome;
    ctx.attempts.push(result.failed);
  }

  if (signal.aborted) return { status: "aborted", usage: {} };
  const allRateLimited = ctx.attempts.length > 0 &&
    ctx.attempts.every((attempt) => attempt.failure === "rate_limited");
  return {
    status: "failed",
    code: allRateLimited ? "rate_limited" : "unavailable",
    attempts: ctx.attempts,
  };
}
