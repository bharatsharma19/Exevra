/**
 * Request validation for ai-chat. Lengths are counted in UTF-16 code units, which is what
 * `String.length` returns in both JavaScript and Dart, so the app can enforce the same limits.
 */
import { HttpError, isRecord } from "../_shared/http.ts";
import type { ChatTurn } from "./types.ts";

export const MAX_MESSAGES = 20;
export const MAX_MESSAGE_CHARS = 4_000;
export const MAX_LAST_USER_CHARS = 2_000;
export const MAX_TOTAL_CHARS = 24_000;
export const ALLOWED_DAYS: readonly number[] = [30, 90, 365];
export const DEFAULT_DAYS = 90;
/** Body cap in bytes: generous enough that the character limits above decide, not the bytes. */
export const MAX_BODY_BYTES = 256 * 1024;

/** A validated ai-chat request. */
export interface ChatRequest {
  messages: ChatTurn[];
  tz: string;
  locale?: string;
  days: number;
}

/** True when `tz` is an IANA zone name the runtime knows. */
export function isValidTimeZone(tz: string): boolean {
  if (tz.length < 1 || tz.length > 64 || !/^[A-Za-z0-9_+\-/]+$/.test(tz)) {
    return false;
  }
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

/** Returns the canonical BCP 47 tag, or `undefined` if `locale` is not valid. */
export function canonicalLocale(locale: string): string | undefined {
  if (
    locale.length < 2 || locale.length > 35 || !/^[A-Za-z0-9-_]+$/.test(locale)
  ) {
    return undefined;
  }
  try {
    return Intl.getCanonicalLocales(locale.replace(/_/g, "-"))[0];
  } catch {
    return undefined;
  }
}

const invalid = (message: string): HttpError => new HttpError("invalid_request", message);
const tooLong = (message: string): HttpError => new HttpError("too_long", message);

/** Validates the parsed JSON body. Throws {@link HttpError} (400 or 413). */
export function parseChatRequest(body: unknown): ChatRequest {
  if (!isRecord(body)) throw invalid("The request body must be a JSON object.");

  const { messages, tz, locale, days } = body;
  if (!Array.isArray(messages) || messages.length === 0) {
    throw invalid("Please send at least one message.");
  }
  if (messages.length > MAX_MESSAGES) {
    throw tooLong("This conversation is too long. Please start a new chat.");
  }

  const turns: ChatTurn[] = [];
  let total = 0;
  for (const message of messages) {
    if (!isRecord(message)) throw invalid("Each message must be an object.");
    const { role, content } = message;
    if (role !== "user" && role !== "assistant") {
      throw invalid("Each message needs a role of user or assistant.");
    }
    if (typeof content !== "string") {
      throw invalid("Each message needs text content.");
    }
    if (content.length > MAX_MESSAGE_CHARS) {
      throw tooLong(
        "One of the messages is too long. Please start a new chat.",
      );
    }
    // Roles must alternate. Same-role runs are rejected rather than merged: merging would let a
    // client split one long message (or a long last message) into turns that each pass the caps.
    if (turns.length > 0 && turns[turns.length - 1].role === role) {
      throw invalid("Messages must alternate between you and the assistant.");
    }
    total += content.length;
    turns.push({ role, content });
  }
  if (total > MAX_TOTAL_CHARS) {
    throw tooLong("This conversation is too long. Please start a new chat.");
  }

  const last = turns[turns.length - 1];
  if (last.role !== "user") throw invalid("The last message must be from you.");
  if (last.content.trim() === "") throw invalid("Please type a message first.");
  if (last.content.length > MAX_LAST_USER_CHARS) {
    throw tooLong(
      `That message is too long. Please keep it under ${MAX_LAST_USER_CHARS} characters.`,
    );
  }

  if (typeof tz !== "string" || !isValidTimeZone(tz)) {
    throw invalid("The time zone is missing or not recognised.");
  }

  let canonical: string | undefined;
  if (locale !== undefined && locale !== null) {
    if (typeof locale !== "string") throw invalid("The locale is not valid.");
    canonical = canonicalLocale(locale);
    if (canonical === undefined) throw invalid("The locale is not valid.");
  }

  let window = DEFAULT_DAYS;
  if (days !== undefined && days !== null) {
    if (typeof days !== "number" || !ALLOWED_DAYS.includes(days)) {
      throw invalid("days must be 30, 90 or 365.");
    }
    window = days;
  }

  return { messages: turns, tz, locale: canonical, days: window };
}
