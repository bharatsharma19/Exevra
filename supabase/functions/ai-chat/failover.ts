/**
 * Provider failover. Providers are tried in order, but only until the first visible text token:
 * after that the answer belongs to that provider, and any failure ends the stream as
 * `interrupted`. Text from two providers is never mixed in one answer.
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

/** Time allowed from starting a provider call to its first text token. */
export const FIRST_TOKEN_TIMEOUT_MS = 12_000;
/** Time allowed between events once text is flowing. */
export const STREAM_IDLE_TIMEOUT_MS = 30_000;

/** Callbacks for streamed output. `onStart` fires exactly once, right before the first text. */
export interface FailoverSink {
  onStart(provider: ProviderName, model: string): void;
  onText(text: string): void;
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

/** Why a provider attempt failed before producing text. */
export type AttemptFailure = ProviderErrorKind | "timeout" | "empty";

/** One provider attempt that failed before any text. */
export interface FailedAttempt {
  provider: ProviderName;
  model: string;
  failure: AttemptFailure;
  status?: number;
}

interface Served {
  provider: ProviderName;
  model: string;
  ttftMs?: number;
  usage: ProviderUsage;
  /** Earlier providers that failed before any text. */
  attempts: FailedAttempt[];
}

/** Result of {@link runWithFailover}. */
export type FailoverOutcome =
  /** The answer completed (`truncated` when it hit the output cap). */
  | (Served & { status: "done"; truncated: boolean })
  /** The provider declined before any text (Claude refusal or Gemini block). No failover. */
  | (Served & { status: "declined" })
  /** The provider failed or declined after text was streamed. */
  | (Served & {
    status: "interrupted";
    reason: "error" | "timeout" | "declined";
  })
  /** Every provider failed before any text. */
  | {
    status: "failed";
    code: "rate_limited" | "unavailable";
    attempts: FailedAttempt[];
  }
  /** The client went away. `provider` is set if text had started. */
  | {
    status: "aborted";
    provider?: ProviderName;
    model?: string;
    usage: ProviderUsage;
  };

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

/** Streams an answer from the first provider that produces text. */
export async function runWithFailover(
  options: FailoverOptions,
): Promise<FailoverOutcome> {
  const { providers, params, signal, sink, clock, timers } = options;
  const firstTokenTimeout = options.firstTokenTimeoutMs ??
    FIRST_TOKEN_TIMEOUT_MS;
  const idleTimeout = options.idleTimeoutMs ?? STREAM_IDLE_TIMEOUT_MS;
  const attempts: FailedAttempt[] = [];

  for (const provider of providers) {
    if (signal.aborted) return { status: "aborted", usage: {} };

    const controller = new AbortController();
    const onClientAbort = (): void => controller.abort(signal.reason);
    signal.addEventListener("abort", onClientAbort, { once: true });

    const started = clock.now();
    const usage: ProviderUsage = {};
    let ttftMs: number | undefined;
    let iterator: AsyncIterator<ProviderEvent> | undefined;
    const served = (): Served => ({
      provider: provider.name,
      model: provider.model,
      ttftMs,
      usage,
      attempts,
    });
    const fail = (failure: AttemptFailure, status?: number): void => {
      attempts.push({
        provider: provider.name,
        model: provider.model,
        failure,
        status,
      });
    };

    try {
      iterator = provider.streamText(params, controller.signal)
        [Symbol.asyncIterator]();
      let outcome: FailoverOutcome | "next" | undefined;

      while (outcome === undefined) {
        const wait = ttftMs === undefined ? started + firstTokenTimeout - clock.now() : idleTimeout;
        let result: Raced<ProviderEvent>;
        try {
          result = await nextOrTimeout(iterator, wait, signal, timers);
        } catch (err) {
          if (signal.aborted) {
            result = ABORTED;
          } else if (ttftMs !== undefined) {
            outcome = { ...served(), status: "interrupted", reason: "error" };
            break;
          } else {
            const providerError = err instanceof ProviderError ? err : undefined;
            fail(providerError?.kind ?? "unavailable", providerError?.status);
            outcome = "next";
            break;
          }
        }

        if (result === ABORTED) {
          outcome = ttftMs === undefined ? { status: "aborted", usage } : {
            status: "aborted",
            provider: provider.name,
            model: provider.model,
            usage,
          };
        } else if (result === TIMEOUT) {
          if (ttftMs === undefined) {
            fail("timeout");
            outcome = "next";
          } else {
            outcome = { ...served(), status: "interrupted", reason: "timeout" };
          }
        } else if (result.done) {
          // Adapters always end with `stop`; ending without one means the stream was cut off.
          if (ttftMs === undefined) {
            fail("unavailable");
            outcome = "next";
          } else {
            outcome = { ...served(), status: "interrupted", reason: "error" };
          }
        } else {
          const event = result.value;
          if (event.type === "usage") {
            mergeUsage(usage, event.usage);
          } else if (event.type === "text") {
            if (event.text === "") continue;
            if (ttftMs === undefined) {
              ttftMs = clock.now() - started;
              sink.onStart(provider.name, provider.model);
            }
            sink.onText(event.text);
          } else if (event.reason === "refusal" || event.reason === "blocked") {
            outcome = ttftMs === undefined
              ? { ...served(), status: "declined" }
              : { ...served(), status: "interrupted", reason: "declined" };
          } else if (ttftMs === undefined) {
            // Finished without any visible text (for example all output went to thinking).
            fail("empty");
            outcome = "next";
          } else {
            outcome = {
              ...served(),
              status: "done",
              truncated: event.reason === "max_tokens",
            };
          }
        }
      }

      if (outcome !== "next") return outcome;
    } catch (err) {
      // streamText itself threw synchronously.
      if (signal.aborted) return { status: "aborted", usage };
      const providerError = err instanceof ProviderError ? err : undefined;
      fail(providerError?.kind ?? "unavailable", providerError?.status);
    } finally {
      signal.removeEventListener("abort", onClientAbort);
      if (iterator) release(iterator, controller);
      else controller.abort();
    }
  }

  if (signal.aborted) return { status: "aborted", usage: {} };
  const allRateLimited = attempts.length > 0 &&
    attempts.every((attempt) => attempt.failure === "rate_limited");
  return {
    status: "failed",
    code: allRateLimited ? "rate_limited" : "unavailable",
    attempts,
  };
}
