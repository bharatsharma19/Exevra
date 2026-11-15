/**
 * Test-only fakes for ai-chat. Never import this from runtime code.
 */
import type { AuthUser, GetUserResult } from "../_shared/auth.ts";
import { envFromRecord, readAiEnv } from "../_shared/env.ts";
import type { PgErrorLike } from "../_shared/http.ts";
import { createLogger } from "../_shared/log.ts";
import { parseSse } from "../_shared/sse.ts";
import { type FakeTimers, fakeTimers, memorySink } from "../_shared/testing.ts";
import type { AiChatClient, AiChatDeps, DbResult } from "./handler.ts";
import type {
  ChatProvider,
  ProviderEvent,
  ProviderName,
  StopReason,
  StreamParams,
} from "./types.ts";

/** A JWT-shaped token (the fake auth client decides whether it is valid). */
export const VALID_TOKEN = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1In0.c2lnbmF0dXJl";
export const TEST_USER: AuthUser = {
  id: "11111111-2222-4333-8444-555555555555",
  email: "person@example.com",
};
export const EVENT_ID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";

// ---- Providers ---------------------------------------------------------------------------

export type ProviderScript = (
  signal: AbortSignal,
  params: StreamParams,
) => AsyncGenerator<ProviderEvent>;

export interface FakeProvider extends ChatProvider {
  readonly calls: Array<{ params: StreamParams; signal: AbortSignal }>;
}

/** A provider driven by `script`. */
export function fakeProvider(
  name: ProviderName,
  script: ProviderScript,
  model = `${name}-test-model`,
): FakeProvider {
  const calls: Array<{ params: StreamParams; signal: AbortSignal }> = [];
  return {
    name,
    model,
    calls,
    streamText(params, signal) {
      calls.push({ params, signal });
      return script(signal, params);
    },
  };
}

/** Yields the given text chunks, usage, then `stop`. */
export function answer(
  chunks: readonly string[],
  reason: StopReason = "end",
  usage = { inputTokens: 120, outputTokens: 30 },
): ProviderScript {
  return async function* () {
    yield { type: "usage", usage: { inputTokens: usage.inputTokens } };
    for (const text of chunks) yield { type: "text", text };
    yield { type: "usage", usage };
    yield { type: "stop", reason };
  };
}

/** Throws `error` before any event. */
export function failing(error: unknown): ProviderScript {
  // deno-lint-ignore require-yield
  return async function* () {
    await Promise.resolve();
    throw error;
  };
}

/** Yields `chunks`, then throws `error`. */
export function failingAfter(
  chunks: readonly string[],
  error: unknown,
): ProviderScript {
  return async function* () {
    for (const text of chunks) yield { type: "text", text };
    throw error;
  };
}

/** Waits until the signal aborts, then throws its reason. Calls `onStart` when invoked. */
export function hanging(
  onStart?: () => void,
  before: readonly ProviderEvent[] = [],
): ProviderScript {
  return async function* (signal) {
    onStart?.();
    for (const event of before) yield event;
    await new Promise<void>((resolve) => {
      if (signal.aborted) resolve();
      signal.addEventListener("abort", () => resolve(), { once: true });
    });
    throw signal.reason ?? new DOMException("aborted", "AbortError");
  };
}

/** A promise with exposed resolve. */
export function deferred<T = void>(): {
  promise: Promise<T>;
  resolve: (value: T) => void;
} {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
}

// ---- Supabase ----------------------------------------------------------------------------

export interface FakeClientOptions {
  user?: AuthUser | null;
  getUserError?: { status?: number; name?: string };
  consent?: boolean | null;
  consentError?: PgErrorLike;
  quota?: DbResult;
  context?: DbResult;
  finish?: DbResult;
}

export interface RpcCall {
  fn: string;
  args: Record<string, unknown>;
}

export interface FakeClient extends AiChatClient {
  readonly rpcCalls: RpcCall[];
  readonly consentReads: string[];
  readonly getUserCalls: Array<string | undefined>;
}

/** Default spending context, shaped like `get_ai_spending_context`. */
export function sampleContext(): Record<string, unknown> {
  return {
    currency: "INR",
    currencies: ["INR"],
    timeframe: { start: "2026-08-17", end: "2026-11-15", tz: "Asia/Kolkata" },
    totals_by_category: [{
      category: "Food",
      currency: "INR",
      amount_minor: 1234500,
    }],
    totals_by_month: [{
      month: "2026-11",
      currency: "INR",
      amount_minor: 456700,
    }],
    recent_expenses: [
      {
        date: "2026-11-14",
        title: "Lunch",
        category: "Food",
        amount_minor: 45000,
        currency: "INR",
        group_name: null,
      },
    ],
    groups: ["Flatmates"],
  };
}

export function fakeClient(options: FakeClientOptions = {}): FakeClient {
  const rpcCalls: RpcCall[] = [];
  const consentReads: string[] = [];
  const getUserCalls: Array<string | undefined> = [];
  const user = options.user === undefined ? TEST_USER : options.user;
  return {
    rpcCalls,
    consentReads,
    getUserCalls,
    auth: {
      getUser(jwt?: string): Promise<GetUserResult> {
        getUserCalls.push(jwt);
        if (options.getUserError) {
          return Promise.resolve({
            data: { user: null },
            error: options.getUserError,
          });
        }
        return Promise.resolve({ data: { user }, error: null });
      },
    },
    rpc(fn, args) {
      rpcCalls.push({ fn, args });
      switch (fn) {
        case "consume_ai_quota":
          return Promise.resolve(
            options.quota ?? { data: EVENT_ID, error: null },
          );
        case "get_ai_spending_context":
          return Promise.resolve(
            options.context ?? { data: sampleContext(), error: null },
          );
        case "finish_ai_usage":
          return Promise.resolve(options.finish ?? { data: null, error: null });
        default:
          return Promise.resolve({
            data: null,
            error: { code: "42883", message: "unknown" },
          });
      }
    },
    readAiConsent(userId) {
      consentReads.push(userId);
      if (options.consentError) {
        return Promise.resolve({ data: null, error: options.consentError });
      }
      const consent = options.consent === undefined ? true : options.consent;
      return Promise.resolve({
        data: consent === null ? null : { ai_consent: consent },
        error: null,
      });
    },
  };
}

// ---- Handler harness ---------------------------------------------------------------------

export interface Harness {
  deps: AiChatDeps<FakeClient>;
  client: FakeClient;
  timers: FakeTimers;
  logs: ReturnType<typeof memorySink>["lines"];
  tasks: Promise<unknown>[];
  /** Authorization headers passed to the client factory. */
  clientsMade: string[];
}

export function harness(
  providers: readonly ChatProvider[],
  clientOptions: FakeClientOptions = {},
  overrides: Partial<AiChatDeps<FakeClient>> = {},
): Harness {
  const timers = fakeTimers(Date.UTC(2026, 10, 15, 6, 30));
  const client = fakeClient(clientOptions);
  const { sink, lines } = memorySink();
  const tasks: Promise<unknown>[] = [];
  const clientsMade: string[] = [];
  const deps: AiChatDeps<FakeClient> = {
    ai: readAiEnv(envFromRecord({ AI_DAILY_QUOTA: "50", AI_PER_MINUTE: "6" })),
    makeClient: (authorization) => {
      clientsMade.push(authorization);
      return client;
    },
    providers,
    clock: timers.clock,
    timers,
    logger: createLogger("ai-chat", { sink, clock: timers.clock }),
    newRequestId: () => "req-1",
    waitUntil: (task) => tasks.push(task),
    pingIntervalMs: 0,
    ...overrides,
  };
  return { deps, client, timers, logs: lines, tasks, clientsMade };
}

export interface ChatBody {
  messages?: unknown;
  tz?: unknown;
  locale?: unknown;
  days?: unknown;
}

export function chatRequest(
  body: ChatBody | string = {},
  options: { token?: string | null; signal?: AbortSignal; method?: string } = {},
): Request {
  const headers = new Headers({ "content-type": "application/json" });
  const token = options.token === undefined ? VALID_TOKEN : options.token;
  if (token !== null) headers.set("authorization", `Bearer ${token}`);
  const payload = typeof body === "string" ? body : JSON.stringify({
    messages: [{ role: "user", content: "How much did I spend on food?" }],
    tz: "Asia/Kolkata",
    ...body,
  });
  return new Request("http://localhost/functions/v1/ai-chat", {
    method: options.method ?? "POST",
    headers,
    body: options.method === "GET" ? undefined : payload,
    signal: options.signal,
  });
}

export interface StreamEvent {
  event: string;
  data: Record<string, unknown>;
}

/** Reads every SSE event from a response body. */
export async function readEvents(response: Response): Promise<StreamEvent[]> {
  const events: StreamEvent[] = [];
  if (response.body === null) return events;
  for await (const message of parseSse(response.body)) {
    events.push({ event: message.event, data: JSON.parse(message.data) });
  }
  return events;
}

/** Concatenated `delta` text. */
export function deltaText(events: readonly StreamEvent[]): string {
  return events.filter((e) => e.event === "delta").map((e) => String(e.data.text)).join("");
}

/** Lets pending promise callbacks run. */
export async function flush(times = 10): Promise<void> {
  for (let i = 0; i < times; i++) {
    await new Promise<void>((r) => setTimeout(r, 0));
  }
}

/**
 * Runs `fn` with an empty `process.env`. The Anthropic SDK reads optional variables when a client
 * is built, and tests run without env permission.
 */
export function withEmptyProcessEnv<T>(fn: () => T): T {
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, "process");
  Object.defineProperty(globalThis, "process", { value: { env: {} }, configurable: true });
  try {
    return fn();
  } finally {
    if (descriptor) Object.defineProperty(globalThis, "process", descriptor);
    else delete (globalThis as { process?: unknown }).process;
  }
}
