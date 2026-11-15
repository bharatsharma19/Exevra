/**
 * Types shared by the ai-chat handler, the failover loop and the provider adapters.
 */

/** Provider names as sent to the app in the `meta` event. */
export type ProviderName = "claude" | "gemini";

/** One chat turn, already validated and normalised (non-empty, alternating, starts with user). */
export interface ChatTurn {
  role: "user" | "assistant";
  content: string;
}

/** Everything a provider needs for one streamed answer. */
export interface StreamParams {
  /** Fixed instructions (product copy). Identical on every request, so it can be cached. */
  instructions: string;
  /** The per-request data block (spending JSON, today's date, locale). */
  context: string;
  /** Conversation history; the last turn is always the user's. */
  turns: readonly ChatTurn[];
  /** Output cap including thinking tokens. */
  maxOutputTokens: number;
}

/** Why a provider stopped. `refusal` (Claude) and `blocked` (Gemini) both mean "declined". */
export type StopReason = "end" | "max_tokens" | "refusal" | "blocked";

/** Token counts reported by a provider. Either field may be unknown. */
export interface ProviderUsage {
  inputTokens?: number;
  outputTokens?: number;
}

/**
 * Events yielded by {@link ChatProvider.streamText}. `text` carries visible answer text only
 * (thinking is never yielded). `usage` may arrive at any point and carries cumulative counts.
 * `progress` carries nothing: it says the upstream stream is alive (for example a thinking delta)
 * and only restarts the idle timer. `stop` is the last event of a completed stream.
 */
export type ProviderEvent =
  | { type: "text"; text: string }
  | { type: "usage"; usage: ProviderUsage }
  | { type: "progress" }
  | { type: "stop"; reason: StopReason };

/** Failure categories that decide the final error code when every provider fails. */
export type ProviderErrorKind =
  | "rate_limited"
  | "unavailable"
  | "bad_request"
  | "auth";

/** Thrown by provider adapters. Never carries provider response bodies or keys. */
export class ProviderError extends Error {
  readonly kind: ProviderErrorKind;
  readonly status?: number;

  constructor(
    kind: ProviderErrorKind,
    options: { status?: number; cause?: unknown } = {},
  ) {
    super(
      `Provider error: ${kind}${options.status !== undefined ? ` (${options.status})` : ""}`,
      {
        cause: options.cause,
      },
    );
    this.name = "ProviderError";
    this.kind = kind;
    this.status = options.status;
  }
}

/** A streaming model provider. */
export interface ChatProvider {
  readonly name: ProviderName;
  readonly model: string;
  /**
   * Streams one answer. Implementations must stop promptly once `signal` aborts, and must throw
   * {@link ProviderError} for provider failures.
   */
  streamText(
    params: StreamParams,
    signal: AbortSignal,
  ): AsyncIterable<ProviderEvent>;
}

/**
 * Maps an HTTP status from a provider to a {@link ProviderErrorKind}. 402 (prepaid credits
 * depleted or another billing problem) is `unavailable`, not `rate_limited`: waiting a minute does
 * not fix it, so the app must not say "busy".
 */
export function kindFromStatus(status: number): ProviderErrorKind {
  if (status === 429) return "rate_limited";
  if (status === 402) return "unavailable";
  if (status === 401 || status === 403) return "auth";
  if (status === 400 || status === 404 || status === 413 || status === 422) {
    return "bad_request";
  }
  return "unavailable";
}
