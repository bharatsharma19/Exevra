/**
 * ai-chat request handler. Pure: every dependency (config, Supabase client factory, providers,
 * clock, timers, logger) is injected, so it runs in tests without network access.
 *
 * Order of checks: method, JWT (401), body and caps (400/413), provider config (503),
 * consent (403, before any data leaves the database), quota (429), then the spending context.
 * Only then is the SSE stream opened. See README.md for the wire protocol.
 */
import { type AuthCapableClient, authenticate, type UserClientFactory } from "../_shared/auth.ts";
import type { Clock, Timers } from "../_shared/clock.ts";
import type { AiEnv } from "../_shared/env.ts";
import {
  assertMethod,
  errorResponseFrom,
  HttpError,
  httpErrorFromPg,
  isRecord,
  type PgErrorLike,
  readJsonBody,
} from "../_shared/http.ts";
import { errorName, type Logger, newRequestId } from "../_shared/log.ts";
import { createSseStream, DEFAULT_PING_INTERVAL_MS, sseResponse } from "../_shared/sse.ts";
import { type FailedAttempt, type FailoverOutcome, runWithFailover } from "./failover.ts";
import { createOutputFilter } from "./output_filter.ts";
import { buildContextBlock, localDate, prepareHistory, SYSTEM_INSTRUCTIONS } from "./prompt.ts";
import { MAX_BODY_BYTES, parseChatRequest } from "./request.ts";
import type { ChatProvider, ProviderUsage, StreamParams } from "./types.ts";

/** Output cap per answer. Thinking counts toward it, hence the margin over a typical answer. */
export const MAX_OUTPUT_TOKENS = 4096;

/** Longest wait for `finish_ai_usage`; usage booking must never hold a worker for long. */
export const FINISH_USAGE_TIMEOUT_MS = 5_000;

/** Result of a Supabase query or RPC. */
export interface DbResult {
  data: unknown;
  error: PgErrorLike | null;
}

/** The caller-scoped database operations ai-chat needs (RLS applies to all of them). */
export interface AiChatClient extends AuthCapableClient {
  /** Calls a Postgres function through PostgREST. */
  rpc(fn: string, args: Record<string, unknown>): PromiseLike<DbResult>;
  /** Reads `profiles.ai_consent` for the caller's own row (`data` is the row or null). */
  readAiConsent(userId: string): PromiseLike<DbResult>;
}

/** Dependencies of {@link handleAiChat}. */
export interface AiChatDeps<C extends AiChatClient> {
  ai: AiEnv;
  makeClient: UserClientFactory<C>;
  /** Providers in failover order (Claude first). Only configured providers are listed. */
  providers: readonly ChatProvider[];
  clock: Clock;
  timers: Timers;
  logger: Logger;
  newRequestId?: () => string;
  /** Keeps the worker alive until the stream task (including usage bookkeeping) finishes. */
  waitUntil?: (task: Promise<unknown>) => void;
  firstTokenTimeoutMs?: number;
  idleTimeoutMs?: number;
  pingIntervalMs?: number;
}

/** Values written to `ai_usage_events.status` by `finish_ai_usage`. */
export type UsageStatus =
  | "ok"
  | "truncated"
  | "declined"
  | "interrupted"
  | "failed"
  | "aborted"
  | "error";

/** Friendly copy sent with stream `error` / `interrupted` events. */
export const STREAM_MESSAGES = {
  declined:
    "I can't help with that one. Ask me about your spending, budgeting or how to use Exevra.",
  unavailable: "The assistant is temporarily unavailable. Please try again in a moment.",
  rate_limited: "The assistant is busy right now. Please try again in a minute.",
  interrupted: "The answer was interrupted. Please try again.",
} as const;

const QUOTA_MESSAGES: Readonly<Record<string, string>> = {
  quota_exceeded: "You've reached today's limit for the assistant. It resets at midnight UTC.",
  rate_limited: "You're sending messages a little fast. Please wait a moment and try again.",
};

/** Seconds until the next UTC midnight (when the daily quota resets), at least 1. */
export function secondsUntilUtcMidnight(now: number): number {
  const date = new Date(now);
  const next = Date.UTC(
    date.getUTCFullYear(),
    date.getUTCMonth(),
    date.getUTCDate() + 1,
  );
  return Math.max(1, Math.ceil((next - now) / 1000));
}

/** Extracts the reserved event id from `consume_ai_quota` (uuid, row or single-row array). */
export function quotaEventId(data: unknown): string | undefined {
  const value = Array.isArray(data) ? data[0] : data;
  if (typeof value === "string" && value !== "") return value;
  if (isRecord(value)) {
    for (const key of ["event_id", "id", "consume_ai_quota"]) {
      const id = value[key];
      if (typeof id === "string" && id !== "") return id;
    }
  }
  return undefined;
}

function mapQuotaError(error: PgErrorLike, now: number): HttpError {
  const mapped = httpErrorFromPg(error);
  if (mapped.code !== "quota_exceeded" && mapped.code !== "rate_limited") {
    return mapped;
  }
  const retryAfter = mapped.code === "quota_exceeded" ? secondsUntilUtcMidnight(now) : 60;
  return new HttpError(mapped.code, QUOTA_MESSAGES[mapped.code], {
    reason: mapped.reason,
    headers: { "retry-after": String(retryAfter) },
    cause: error,
  });
}

interface UsageRecord {
  status: UsageStatus;
  provider: string | null;
  model: string | null;
  usage: ProviderUsage;
  /** Time from the start of the request to the first text token. */
  ttftMs?: number;
  /** Time from the serving provider's start to its first text token. */
  providerTtftMs?: number;
  latencyMs: number;
}

/** Sums the tokens of attempts that failed before any text (logged as `failover_*_tokens`). */
function attemptUsage(attempts: readonly FailedAttempt[]): ProviderUsage {
  const total: ProviderUsage = {};
  for (const { usage } of attempts) {
    if (usage.inputTokens !== undefined) {
      total.inputTokens = (total.inputTokens ?? 0) + usage.inputTokens;
    }
    if (usage.outputTokens !== undefined) {
      total.outputTokens = (total.outputTokens ?? 0) + usage.outputTokens;
    }
  }
  return total;
}

/** Handles one ai-chat request. */
export async function handleAiChat<C extends AiChatClient>(
  req: Request,
  deps: AiChatDeps<C>,
): Promise<Response> {
  const { clock, logger } = deps;
  const requestId = (deps.newRequestId ?? newRequestId)();
  const started = clock.now();

  let client: C | undefined;
  let eventId: string | undefined;

  const finishUsage = async (record: UsageRecord): Promise<void> => {
    if (client === undefined || eventId === undefined) return;
    let timer: ReturnType<Timers["setTimeout"]> | undefined;
    try {
      const call = Promise.resolve(
        client.rpc("finish_ai_usage", {
          p_event_id: eventId,
          p_provider: record.provider,
          p_model: record.model,
          p_status: record.status,
          p_latency_ms: Math.max(0, Math.round(record.latencyMs)),
          p_input_tokens: record.usage.inputTokens ?? null,
          p_output_tokens: record.usage.outputTokens ?? null,
        }),
      );
      const timeout = new Promise<"timeout">((resolve) => {
        timer = deps.timers.setTimeout(() => resolve("timeout"), FINISH_USAGE_TIMEOUT_MS);
      });
      const result = await Promise.race([call, timeout]);
      if (result === "timeout") {
        call.catch(() => {});
        logger.warn({ request_id: requestId, step: "finish_ai_usage", error: "timeout" });
        return;
      }
      const { error } = result;
      if (error) {
        logger.warn({
          request_id: requestId,
          step: "finish_ai_usage",
          code: error.code,
        });
      }
    } catch (err) {
      logger.warn({
        request_id: requestId,
        step: "finish_ai_usage",
        error: errorName(err),
      });
    } finally {
      if (timer !== undefined) deps.timers.clearTimeout(timer);
    }
  };

  let params: StreamParams;
  try {
    assertMethod(req, "POST");
    const auth = await authenticate(req, deps.makeClient);
    client = auth.client;
    const chat = parseChatRequest(
      await readJsonBody(req, { maxBytes: MAX_BODY_BYTES }),
    );

    if (deps.providers.length === 0) {
      throw new HttpError(
        "unavailable",
        "The assistant isn't available right now.",
      );
    }

    // Consent gate: nothing is read for the model and nothing is sent anywhere without it.
    const consent = await auth.client.readAiConsent(auth.user.id);
    if (consent.error) throw httpErrorFromPg(consent.error);
    if (!isRecord(consent.data) || consent.data.ai_consent !== true) {
      throw new HttpError("consent_required");
    }

    const quota = await auth.client.rpc("consume_ai_quota", {
      p_daily_limit: deps.ai.dailyQuota,
      p_per_minute: deps.ai.perMinute,
    });
    if (quota.error) throw mapQuotaError(quota.error, clock.now());
    eventId = quotaEventId(quota.data);
    if (eventId === undefined) {
      logger.warn({ request_id: requestId, step: "consume_ai_quota" });
    }

    const spending = await auth.client.rpc("get_ai_spending_context", {
      p_tz: chat.tz,
      p_days: chat.days,
    });
    if (spending.error) throw httpErrorFromPg(spending.error);

    params = {
      instructions: SYSTEM_INSTRUCTIONS,
      context: buildContextBlock({
        spending: spending.data,
        timezone: chat.tz,
        locale: chat.locale,
        today: localDate(clock.now(), chat.tz),
        days: chat.days,
      }),
      turns: prepareHistory(chat.messages),
      maxOutputTokens: MAX_OUTPUT_TOKENS,
    };
  } catch (err) {
    const response = errorResponseFrom(err);
    const latencyMs = clock.now() - started;
    await finishUsage({
      status: "error",
      provider: null,
      model: null,
      usage: {},
      latencyMs,
    });
    const line = {
      request_id: requestId,
      status: err instanceof HttpError ? err.code : "internal",
      http_status: response.status,
      latency_ms: latencyMs,
      error: err instanceof HttpError ? undefined : errorName(err),
    };
    if (response.status >= 500) logger.error(line);
    else logger.info(line);
    return response;
  }

  // ---- Streaming -------------------------------------------------------------------------
  const clientAbort = new AbortController();
  const abort = (): void => {
    if (!clientAbort.signal.aborted) clientAbort.abort();
  };
  if (req.signal.aborted) abort();
  else req.signal.addEventListener("abort", abort, { once: true });

  const { stream, writer } = createSseStream({
    pingIntervalMs: deps.pingIntervalMs ?? DEFAULT_PING_INTERVAL_MS,
    timers: deps.timers,
    onCancel: abort,
  });

  // Model text passes through the image filter (see output_filter.ts). `meta` is sent with the
  // first visible text, so it never appears without a following `delta`.
  const filter = createOutputFilter();
  let provider: string | undefined;
  let metaSent = false;
  const sendText = (text: string): void => {
    if (text === "" || provider === undefined) return;
    if (!metaSent) {
      metaSent = true;
      writer.event("meta", { provider, request_id: requestId });
    }
    writer.event("delta", { text });
  };

  const task = (async (): Promise<void> => {
    let outcome: FailoverOutcome;
    try {
      outcome = await runWithFailover({
        providers: deps.providers,
        params,
        signal: clientAbort.signal,
        clock,
        timers: deps.timers,
        firstTokenTimeoutMs: deps.firstTokenTimeoutMs,
        idleTimeoutMs: deps.idleTimeoutMs,
        sink: {
          onStart: (name) => {
            provider = name;
          },
          onText: (text) => sendText(filter.push(text)),
        },
      });
    } catch (err) {
      // runWithFailover does not throw; this is a last line of defence.
      logger.error({
        request_id: requestId,
        step: "failover",
        error: errorName(err),
      });
      outcome = { status: "failed", code: "unavailable", attempts: [] };
    }

    // Release text held back by the filter before the terminal event (not after an abort).
    if (outcome.status !== "aborted") sendText(filter.flush());

    let record: UsageRecord;
    const latencyMs = clock.now() - started;
    const ttft = "firstTokenAt" in outcome && outcome.firstTokenAt !== undefined
      ? {
        ttftMs: outcome.firstTokenAt - started,
        providerTtftMs: outcome.ttftMs,
      }
      : {};
    switch (outcome.status) {
      case "done":
        writer.event("done", { truncated: outcome.truncated });
        record = {
          status: outcome.truncated ? "truncated" : "ok",
          provider: outcome.provider,
          model: outcome.model,
          usage: outcome.usage,
          ...ttft,
          latencyMs,
        };
        break;
      case "declined":
        writer.event("error", {
          code: "declined",
          message: STREAM_MESSAGES.declined,
        });
        record = {
          status: "declined",
          provider: outcome.provider,
          model: outcome.model,
          usage: outcome.usage,
          latencyMs,
        };
        break;
      case "interrupted":
        writer.event("interrupted", {
          code: "interrupted",
          reason: outcome.reason,
          message: STREAM_MESSAGES.interrupted,
        });
        record = {
          status: "interrupted",
          provider: outcome.provider,
          model: outcome.model,
          usage: outcome.usage,
          ...ttft,
          latencyMs,
        };
        break;
      case "failed": {
        writer.event("error", {
          code: outcome.code,
          message: STREAM_MESSAGES[outcome.code],
        });
        const last = outcome.attempts[outcome.attempts.length - 1];
        record = {
          status: "failed",
          provider: last?.provider ?? null,
          model: last?.model ?? null,
          usage: last?.usage ?? {},
          latencyMs,
        };
        break;
      }
      case "aborted":
        record = {
          status: "aborted",
          provider: outcome.provider ?? null,
          model: outcome.model ?? null,
          usage: outcome.usage,
          latencyMs,
        };
        break;
    }

    // End the response right after the terminal event; usage booking and the log line run
    // afterwards inside this task, which waitUntil keeps alive.
    writer.close();
    req.signal.removeEventListener("abort", abort);
    await finishUsage(record);

    const attempts = "attempts" in outcome ? outcome.attempts : [];
    // When every provider failed, the last attempt's tokens are already in `record.usage`.
    const failedTokens = attemptUsage(
      outcome.status === "failed" ? attempts.slice(0, -1) : attempts,
    );
    const line = {
      request_id: requestId,
      provider: record.provider,
      model: record.model,
      status: record.status,
      http_status: 200,
      ttft_ms: record.ttftMs,
      provider_ttft_ms: record.providerTtftMs,
      latency_ms: record.latencyMs,
      input_tokens: record.usage.inputTokens,
      output_tokens: record.usage.outputTokens,
      failover: attempts.length > 0
        ? attempts.map((a) => `${a.provider}:${a.failure}`).join(",")
        : undefined,
      failover_input_tokens: failedTokens.inputTokens,
      failover_output_tokens: failedTokens.outputTokens,
    };
    if (
      record.status === "ok" || record.status === "truncated" ||
      record.status === "aborted"
    ) {
      logger.info(line);
    } else {
      logger.warn(line);
    }
  })();

  deps.waitUntil?.(task);
  return sseResponse(stream, { "x-request-id": requestId });
}
