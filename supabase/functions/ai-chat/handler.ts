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
import { type FailoverOutcome, runWithFailover } from "./failover.ts";
import { buildContextBlock, localDate, prepareHistory, SYSTEM_INSTRUCTIONS } from "./prompt.ts";
import { MAX_BODY_BYTES, parseChatRequest } from "./request.ts";
import type { ChatProvider, ProviderUsage, StreamParams } from "./types.ts";

/** Output cap per answer. Thinking counts toward it, hence the margin over a typical answer. */
export const MAX_OUTPUT_TOKENS = 4096;

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
  ttftMs?: number;
  latencyMs: number;
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
    try {
      const { error } = await client.rpc("finish_ai_usage", {
        p_event_id: eventId,
        p_provider: record.provider,
        p_model: record.model,
        p_status: record.status,
        p_latency_ms: Math.max(0, Math.round(record.latencyMs)),
        p_input_tokens: record.usage.inputTokens ?? null,
        p_output_tokens: record.usage.outputTokens ?? null,
      });
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
          onStart: (provider) => writer.event("meta", { provider, request_id: requestId }),
          onText: (text) => writer.event("delta", { text }),
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

    let record: UsageRecord;
    const latencyMs = clock.now() - started;
    switch (outcome.status) {
      case "done":
        writer.event("done", { truncated: outcome.truncated });
        record = {
          status: outcome.truncated ? "truncated" : "ok",
          provider: outcome.provider,
          model: outcome.model,
          usage: outcome.usage,
          ttftMs: outcome.ttftMs,
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
          ttftMs: outcome.ttftMs,
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
          usage: {},
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

    // Book usage before closing so the worker is still alive for the RPC.
    await finishUsage(record);
    req.signal.removeEventListener("abort", abort);

    const line = {
      request_id: requestId,
      provider: record.provider,
      model: record.model,
      status: record.status,
      http_status: 200,
      ttft_ms: record.ttftMs,
      latency_ms: record.latencyMs,
      input_tokens: record.usage.inputTokens,
      output_tokens: record.usage.outputTokens,
      failover: "attempts" in outcome && outcome.attempts.length > 0
        ? outcome.attempts.map((a) => `${a.provider}:${a.failure}`).join(",")
        : undefined,
    };
    if (
      record.status === "ok" || record.status === "truncated" ||
      record.status === "aborted"
    ) {
      logger.info(line);
    } else {
      logger.warn(line);
    }
    writer.close();
  })();

  deps.waitUntil?.(task);
  return sseResponse(stream, { "x-request-id": requestId });
}
