/**
 * Claude adapter: streams an answer with the official Anthropic SDK and turns SDK stream events
 * into {@link ProviderEvent}s. Only `text_delta` content reaches the app; thinking, signature and
 * server-side `fallback` blocks are ignored.
 */
import Anthropic from "npm:@anthropic-ai/sdk@1.8.0";
import {
  type ChatProvider,
  kindFromStatus,
  ProviderError,
  type ProviderErrorKind,
  type ProviderEvent,
  type StopReason,
  type StreamParams,
} from "../types.ts";

/** The model that supports the server-side refusal fallback (`fallbacks: "default"`). */
export const CLAUDE_SONNET_MODEL = "claude-sonnet-5-5";
/** Beta flag required by `fallbacks: "default"`. */
export const SERVER_SIDE_FALLBACK_BETA = "server-side-fallback-2026-07-01";

/** Request body sent to `messages.stream` (no temperature/top_p/top_k: current models reject them). */
export interface ClaudeRequestBody {
  model: string;
  max_tokens: number;
  system: Array<
    { type: "text"; text: string; cache_control?: { type: "ephemeral" } }
  >;
  messages: Array<{ role: "user" | "assistant"; content: string }>;
  output_config: { effort: "low" };
}

interface ClaudeUsageLike {
  input_tokens?: number | null;
  output_tokens?: number | null;
  cache_creation_input_tokens?: number | null;
  cache_read_input_tokens?: number | null;
}

/** The fields of SDK stream events this adapter reads. */
export interface ClaudeStreamEventLike {
  type: string;
  delta?: { type?: string; text?: string; stop_reason?: string | null };
  message?: { usage?: ClaudeUsageLike };
  usage?: ClaudeUsageLike;
}

/** Opens one SDK stream. Injected in tests; {@link sdkStreamOpener} is the real one. */
export type ClaudeStreamOpener = (
  body: ClaudeRequestBody,
  signal: AbortSignal,
) => AsyncIterable<ClaudeStreamEventLike>;

/** Options for {@link createClaudeProvider}. */
export interface ClaudeProviderOptions {
  model: string;
  /** Opens the SDK stream; see {@link sdkStreamOpener}. */
  open: ClaudeStreamOpener;
}

/** Default API origin, passed explicitly so `ANTHROPIC_BASE_URL` cannot redirect requests. */
export const ANTHROPIC_API_BASE = "https://api.anthropic.com";

/**
 * Creates an SDK client with one retry and a 60 s request timeout. `maxRetries` can be lowered
 * in tests. Chat streams override it per request (see {@link sdkStreamOpener}).
 *
 * `logLevel` and `openTelemetry` are pinned like `baseURL`: otherwise `ANTHROPIC_LOG=debug|info`
 * or `ANTHROPIC_OPEN_TELEMETRY_TRACES_CONTENT_MODE=content` set as a function secret would make
 * the SDK log or trace full requests, including the spending data block and user messages.
 */
export function createAnthropicClient(
  apiKey: string,
  options: { maxRetries?: number } = {},
): Anthropic {
  return new Anthropic({
    apiKey,
    baseURL: ANTHROPIC_API_BASE,
    webhookKey: null,
    maxRetries: options.maxRetries ?? 1,
    timeout: 60_000,
    logLevel: "warn",
    openTelemetry: false,
  });
}

/**
 * Real stream opener. For Claude Sonnet 5.5 it uses the beta endpoint with the server-side
 * refusal fallback; Claude Haiku has no server-side fallback, so it uses the plain endpoint.
 *
 * SDK retries are off for the stream (`maxRetries: 0`): failover to Gemini is the retry. With
 * retries on, the SDK sleeps for the whole `retry-after` of a 429 (any length) before retrying,
 * which runs past the first-token deadline and turns a rate limit into a timeout.
 */
export function sdkStreamOpener(client: Anthropic): ClaudeStreamOpener {
  return (body, signal) => {
    const options = { signal, maxRetries: 0 };
    if (body.model === CLAUDE_SONNET_MODEL) {
      return client.beta.messages.stream(
        { ...body, betas: [SERVER_SIDE_FALLBACK_BETA], fallbacks: "default" },
        options,
      );
    }
    return client.messages.stream(body, options);
  };
}

/** Builds the request body for {@link StreamParams}. */
export function buildClaudeRequest(
  model: string,
  params: StreamParams,
): ClaudeRequestBody {
  return {
    model,
    max_tokens: params.maxOutputTokens,
    system: [
      // The instructions never change, so they form a cacheable prefix.
      {
        type: "text",
        text: params.instructions,
        cache_control: { type: "ephemeral" },
      },
      { type: "text", text: params.context },
    ],
    messages: params.turns.map((turn) => ({
      role: turn.role,
      content: turn.content,
    })),
    output_config: { effort: "low" },
  };
}

/**
 * Error `type`s that decide the kind regardless of the HTTP status. An SSE `error` event inside a
 * 200 stream (for example `overloaded_error` or `rate_limit_error` after `message_start`) reaches
 * us as a plain `APIError` with no status, so its `type` is the only signal. `billing_error`
 * (HTTP 402, for example prepaid credits used up) is `unavailable`: retrying in a minute does not
 * help, so it must not become `rate_limited`.
 */
const CLAUDE_ERROR_TYPE_KINDS: Readonly<Record<string, ProviderErrorKind>> = {
  rate_limit_error: "rate_limited",
  overloaded_error: "unavailable",
  api_error: "unavailable",
  timeout_error: "unavailable",
  billing_error: "unavailable",
};

/**
 * Maps an SDK error to a {@link ProviderError}: the API error `type` first (see
 * {@link CLAUDE_ERROR_TYPE_KINDS}), then the most specific class. `APIConnectionError` is checked
 * before `APIError` because it is a subclass in the TS SDK.
 */
export function mapClaudeError(err: unknown): ProviderError {
  if (err instanceof ProviderError) return err;
  if (err instanceof Anthropic.APIError && typeof err.type === "string") {
    const kind = CLAUDE_ERROR_TYPE_KINDS[err.type];
    if (kind !== undefined) {
      const status = typeof err.status === "number" ? err.status : undefined;
      return new ProviderError(kind, { status, cause: err });
    }
  }
  if (err instanceof Anthropic.RateLimitError) {
    return new ProviderError("rate_limited", { status: 429, cause: err });
  }
  if (err instanceof Anthropic.APIConnectionError) {
    return new ProviderError("unavailable", { cause: err });
  }
  if (err instanceof Anthropic.InternalServerError) {
    return new ProviderError("unavailable", { status: err.status, cause: err });
  }
  if (
    err instanceof Anthropic.AuthenticationError ||
    err instanceof Anthropic.PermissionDeniedError
  ) {
    return new ProviderError("auth", { status: err.status, cause: err });
  }
  if (
    err instanceof Anthropic.NotFoundError ||
    err instanceof Anthropic.BadRequestError
  ) {
    return new ProviderError("bad_request", { status: err.status, cause: err });
  }
  if (err instanceof Anthropic.APIError) {
    const status = typeof err.status === "number" ? err.status : undefined;
    return new ProviderError(
      status === undefined ? "unavailable" : kindFromStatus(status),
      {
        status,
        cause: err,
      },
    );
  }
  return new ProviderError("unavailable", { cause: err });
}

/** Maps a Claude `stop_reason` to a {@link StopReason}. */
export function mapClaudeStopReason(reason: string): StopReason {
  switch (reason) {
    case "max_tokens":
    case "model_context_window_exceeded":
      return "max_tokens";
    case "refusal":
      return "refusal";
    default:
      // end_turn, stop_sequence (and anything unexpected: there are no tools here).
      return "end";
  }
}

const count = (value: number | null | undefined): number =>
  typeof value === "number" && Number.isFinite(value) ? value : 0;

/** Creates the Claude {@link ChatProvider}. */
export function createClaudeProvider(
  options: ClaudeProviderOptions,
): ChatProvider {
  const { model, open } = options;
  return {
    name: "claude",
    model,
    async *streamText(
      params: StreamParams,
      signal: AbortSignal,
    ): AsyncGenerator<ProviderEvent> {
      const body = buildClaudeRequest(model, params);
      let inputTokens: number | undefined;
      let stop: StopReason | undefined;
      try {
        for await (const event of open(body, signal)) {
          let yielded = false;
          switch (event.type) {
            case "message_start": {
              const usage = event.message?.usage;
              if (usage) {
                inputTokens = count(usage.input_tokens) +
                  count(usage.cache_creation_input_tokens) +
                  count(usage.cache_read_input_tokens);
                yield { type: "usage", usage: { inputTokens } };
                yielded = true;
              }
              break;
            }
            case "content_block_delta": {
              // Only visible answer text; thinking_delta / signature_delta are skipped.
              const delta = event.delta;
              if (
                delta?.type === "text_delta" &&
                typeof delta.text === "string" && delta.text
              ) {
                yield { type: "text", text: delta.text };
                yielded = true;
              }
              break;
            }
            case "message_delta": {
              const usage = event.usage;
              if (usage) {
                if (typeof usage.input_tokens === "number") {
                  inputTokens = count(usage.input_tokens) +
                    count(usage.cache_creation_input_tokens) +
                    count(usage.cache_read_input_tokens);
                }
                yield {
                  type: "usage",
                  usage: {
                    inputTokens,
                    outputTokens: count(usage.output_tokens),
                  },
                };
                yielded = true;
              }
              const reason = event.delta?.stop_reason;
              if (typeof reason === "string") {
                stop = mapClaudeStopReason(reason);
              }
              break;
            }
            default:
              // message_stop, content_block_start/stop (text, thinking, fallback ...).
              break;
          }
          // Thinking and other ignored events still show the stream is alive.
          if (!yielded) yield { type: "progress" };
        }
      } catch (err) {
        throw mapClaudeError(err);
      }
      if (stop === undefined) {
        // The stream closed without a stop_reason: treat it as a dropped connection.
        throw new ProviderError("unavailable");
      }
      yield { type: "stop", reason: stop };
    },
  };
}
