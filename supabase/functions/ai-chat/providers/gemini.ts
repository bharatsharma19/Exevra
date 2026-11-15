/**
 * Gemini adapter: `models/{model}:streamGenerateContent?alt=sse` over plain fetch. The API key
 * travels in the `x-goog-api-key` header, never in the URL. Thought parts are skipped.
 */
import { isRecord } from "../../_shared/http.ts";
import { parseSse } from "../../_shared/sse.ts";
import {
  type ChatProvider,
  kindFromStatus,
  ProviderError,
  type ProviderEvent,
  type ProviderUsage,
  type StopReason,
  type StreamParams,
} from "../types.ts";

/** Default API origin. */
export const GEMINI_API_BASE = "https://generativelanguage.googleapis.com";

/** Finish reasons that mean the answer was withheld (declined before text, interrupted after). */
export const GEMINI_BLOCKED_FINISH_REASONS: ReadonlySet<string> = new Set([
  "SAFETY",
  "RECITATION",
  "BLOCKLIST",
  "PROHIBITED_CONTENT",
  "SPII",
  "LANGUAGE",
  "OTHER",
  "IMAGE_SAFETY",
  "IMAGE_PROHIBITED_CONTENT",
  "IMAGE_OTHER",
  "IMAGE_RECITATION",
]);

/** Request body for `streamGenerateContent` (camelCase JSON). */
export interface GeminiRequestBody {
  systemInstruction: { parts: Array<{ text: string }> };
  contents: Array<{ role: "user" | "model"; parts: Array<{ text: string }> }>;
  generationConfig: {
    maxOutputTokens: number;
    // gemini-3.8-flash rejects "minimal"; thinkingBudget must not be sent alongside thinkingLevel.
    thinkingConfig: { thinkingLevel: "low" };
  };
}

/** Options for {@link createGeminiProvider}. */
export interface GeminiProviderOptions {
  apiKey: string;
  model: string;
  /** Override for tests; defaults to `globalThis.fetch` at call time. */
  fetch?: typeof fetch;
  /** Override for tests; defaults to {@link GEMINI_API_BASE}. */
  baseUrl?: string;
}

/** Builds the request body for {@link StreamParams}. */
export function buildGeminiRequest(params: StreamParams): GeminiRequestBody {
  return {
    systemInstruction: {
      parts: [{ text: params.instructions }, { text: params.context }],
    },
    contents: params.turns.map((turn) => ({
      role: turn.role === "assistant" ? "model" : "user",
      parts: [{ text: turn.content }],
    })),
    generationConfig: {
      maxOutputTokens: params.maxOutputTokens,
      thinkingConfig: { thinkingLevel: "low" },
    },
  };
}

/** Builds the stream URL. The key is never part of it. */
export function geminiStreamUrl(
  model: string,
  baseUrl: string = GEMINI_API_BASE,
): string {
  return `${baseUrl}/v1beta/models/${encodeURIComponent(model)}:streamGenerateContent?alt=sse`;
}

/** Maps a candidate `finishReason`; `undefined` while the candidate is still streaming. */
export function mapGeminiFinishReason(
  reason: unknown,
): StopReason | "error" | undefined {
  if (
    typeof reason !== "string" || reason === "" ||
    reason === "FINISH_REASON_UNSPECIFIED"
  ) {
    return undefined;
  }
  if (reason === "STOP") return "end";
  if (reason === "MAX_TOKENS") return "max_tokens";
  if (GEMINI_BLOCKED_FINISH_REASONS.has(reason)) return "blocked";
  // MALFORMED_RESPONSE, UNEXPECTED_TOOL_CALL and other non-content failures.
  return "error";
}

const tokenCount = (value: unknown): number | undefined =>
  typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : undefined;

/** Reads `usageMetadata`; output counts include thinking tokens (both are billed as output). */
export function geminiUsage(metadata: unknown): ProviderUsage | undefined {
  if (!isRecord(metadata)) return undefined;
  const input = tokenCount(metadata.promptTokenCount);
  const candidates = tokenCount(metadata.candidatesTokenCount);
  const thoughts = tokenCount(metadata.thoughtsTokenCount);
  const output = candidates === undefined && thoughts === undefined
    ? undefined
    : (candidates ?? 0) + (thoughts ?? 0);
  if (input === undefined && output === undefined) return undefined;
  return { inputTokens: input, outputTokens: output };
}

/** Maps an in-stream `error` object (`{ code, status }`) to a {@link ProviderError}. */
function streamError(error: Record<string, unknown>): ProviderError {
  const code = typeof error.code === "number" ? error.code : undefined;
  if (code !== undefined) {
    return new ProviderError(kindFromStatus(code), { status: code });
  }
  if (error.status === "RESOURCE_EXHAUSTED") {
    return new ProviderError("rate_limited");
  }
  return new ProviderError("unavailable");
}

/** Creates the Gemini {@link ChatProvider}. */
export function createGeminiProvider(
  options: GeminiProviderOptions,
): ChatProvider {
  const { apiKey, model } = options;
  const url = geminiStreamUrl(model, options.baseUrl);
  return {
    name: "gemini",
    model,
    async *streamText(
      params: StreamParams,
      signal: AbortSignal,
    ): AsyncGenerator<ProviderEvent> {
      const doFetch = options.fetch ?? globalThis.fetch;
      let response: Response;
      try {
        response = await doFetch(url, {
          method: "POST",
          headers: {
            "content-type": "application/json",
            "x-goog-api-key": apiKey,
          },
          body: JSON.stringify(buildGeminiRequest(params)),
          signal,
        });
      } catch (err) {
        throw new ProviderError("unavailable", { cause: err });
      }

      if (!response.ok || response.body === null) {
        // Never read or log the body: it may echo request content.
        await response.body?.cancel().catch(() => {});
        throw new ProviderError(kindFromStatus(response.status), {
          status: response.status,
        });
      }

      let stop: StopReason | undefined;
      try {
        for await (const message of parseSse(response.body, { signal })) {
          const data = message.data.trim();
          if (data === "" || data === "[DONE]") continue;
          let chunk: unknown;
          try {
            chunk = JSON.parse(data);
          } catch (err) {
            throw new ProviderError("unavailable", { cause: err });
          }
          if (!isRecord(chunk)) continue;
          if (isRecord(chunk.error)) throw streamError(chunk.error);

          const usage = geminiUsage(chunk.usageMetadata);
          if (usage) yield { type: "usage", usage };

          const feedback = chunk.promptFeedback;
          if (isRecord(feedback) && typeof feedback.blockReason === "string") {
            if (feedback.blockReason !== "BLOCK_REASON_UNSPECIFIED") {
              stop = "blocked";
              break;
            }
          }

          const candidate = Array.isArray(chunk.candidates) ? chunk.candidates[0] : undefined;
          if (!isRecord(candidate)) continue;
          const content = candidate.content;
          if (isRecord(content) && Array.isArray(content.parts)) {
            for (const part of content.parts) {
              if (!isRecord(part) || part.thought === true) continue;
              if (typeof part.text === "string" && part.text !== "") {
                yield { type: "text", text: part.text };
              }
            }
          }
          const finish = mapGeminiFinishReason(candidate.finishReason);
          if (finish === "error") throw new ProviderError("unavailable");
          if (finish !== undefined) {
            stop = finish;
            break;
          }
        }
      } catch (err) {
        if (err instanceof ProviderError) throw err;
        throw new ProviderError("unavailable", { cause: err });
      }

      // A stream that ends without a finish reason was cut off.
      if (stop === undefined) throw new ProviderError("unavailable");
      yield { type: "stop", reason: stop };
    },
  };
}
