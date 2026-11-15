/**
 * ai-chat entry point: wires real dependencies into the pure handler. No logic lives here.
 */
import { systemClock, systemTimers } from "../_shared/clock.ts";
import { readAiEnv, readSupabaseEnv } from "../_shared/env.ts";
import { errorResponse } from "../_shared/http.ts";
import { createLogger, errorName } from "../_shared/log.ts";
import { handleAiChat } from "./handler.ts";
import {
  createAnthropicClient,
  createClaudeProvider,
  sdkStreamOpener,
} from "./providers/claude.ts";
import { createGeminiProvider } from "./providers/gemini.ts";
import { aiChatClientFactory } from "./supabase.ts";
import type { ChatProvider } from "./types.ts";

const logger = createLogger("ai-chat");
const ai = readAiEnv();

const providers: ChatProvider[] = [];
if (ai.anthropicApiKey) {
  providers.push(
    createClaudeProvider({
      model: ai.claudeModel,
      open: sdkStreamOpener(createAnthropicClient(ai.anthropicApiKey)),
    }),
  );
}
if (ai.geminiApiKey) {
  providers.push(
    createGeminiProvider({ apiKey: ai.geminiApiKey, model: ai.geminiModel }),
  );
}

let makeClient: ReturnType<typeof aiChatClientFactory> | undefined;
try {
  makeClient = aiChatClientFactory(readSupabaseEnv());
} catch (err) {
  logger.error({ step: "config", error: errorName(err) });
}

interface EdgeRuntimeGlobal {
  EdgeRuntime?: { waitUntil(task: Promise<unknown>): void };
}
const edgeRuntime = (globalThis as EdgeRuntimeGlobal).EdgeRuntime;

Deno.serve((req: Request): Promise<Response> | Response => {
  if (makeClient === undefined) return errorResponse("unavailable");
  return handleAiChat(req, {
    ai,
    makeClient,
    providers,
    clock: systemClock,
    timers: systemTimers,
    logger,
    waitUntil: edgeRuntime ? (task) => edgeRuntime.waitUntil(task) : undefined,
  });
});
