/**
 * JSON response and error helpers shared by every Edge Function.
 *
 * Error responses always have the shape `{ error: { code, message, reason? } }` where `code` is a
 * stable {@link ErrorCode} the app switches on, `message` is friendly copy safe to show to users,
 * and `reason` (optional) is a stable database business-rule key such as `invite_expired`.
 */

/** Stable error codes returned to the app. */
export const ERROR_CODES = [
  "invalid_request",
  "unauthorized",
  "consent_required",
  "forbidden",
  "reauth_required",
  "not_found",
  "method_not_allowed",
  "conflict",
  "too_long",
  "quota_exceeded",
  "rate_limited",
  "internal",
  "unavailable",
] as const;

export type ErrorCode = typeof ERROR_CODES[number];

/** HTTP status for each {@link ErrorCode}. */
export const ERROR_STATUS: Readonly<Record<ErrorCode, number>> = {
  invalid_request: 400,
  unauthorized: 401,
  consent_required: 403,
  forbidden: 403,
  reauth_required: 403,
  not_found: 404,
  method_not_allowed: 405,
  conflict: 409,
  too_long: 413,
  quota_exceeded: 429,
  rate_limited: 429,
  internal: 500,
  unavailable: 503,
};

/** Default friendly message for each {@link ErrorCode}. */
export const DEFAULT_ERROR_MESSAGES: Readonly<Record<ErrorCode, string>> = {
  invalid_request: "Something about that request wasn't right. Please try again.",
  unauthorized: "Your session has expired. Please sign in again.",
  consent_required: "Turn on the AI assistant in Settings to use this feature.",
  forbidden: "You don't have permission to do that.",
  reauth_required: "For your security, please sign in again and then try once more.",
  not_found: "We couldn't find what you were looking for.",
  method_not_allowed: "That action isn't supported.",
  conflict: "That couldn't be completed. Please refresh and try again.",
  too_long: "That message is too long. Please shorten it and try again.",
  quota_exceeded: "You've reached today's limit. Please try again tomorrow.",
  rate_limited: "You're going a little fast. Please wait a moment and try again.",
  internal: "Something went wrong on our side. Please try again.",
  unavailable: "This service is temporarily unavailable. Please try again shortly.",
};

/** Returns true when `value` is a known {@link ErrorCode}. */
export function isErrorCode(value: unknown): value is ErrorCode {
  return typeof value === "string" && (ERROR_CODES as readonly string[]).includes(value);
}

/** JSON error body sent to the app. */
export interface ErrorBody {
  error: { code: ErrorCode; message: string; reason?: string };
}

/** Options for {@link HttpError}. */
export interface HttpErrorOptions {
  /** Stable business-rule key for the app (for example `invite_expired`). */
  reason?: string;
  /** Extra response headers, e.g. `retry-after`. */
  headers?: HeadersInit;
  cause?: unknown;
}

/** An error that maps directly to an HTTP error response. */
export class HttpError extends Error {
  readonly code: ErrorCode;
  readonly status: number;
  readonly reason?: string;
  readonly headers?: HeadersInit;

  constructor(code: ErrorCode, message?: string, options: HttpErrorOptions = {}) {
    super(message ?? DEFAULT_ERROR_MESSAGES[code], { cause: options.cause });
    this.name = "HttpError";
    this.code = code;
    this.status = ERROR_STATUS[code];
    this.reason = options.reason;
    this.headers = options.headers;
  }

  /** Builds the JSON body for this error. */
  toBody(): ErrorBody {
    const body: ErrorBody = { error: { code: this.code, message: this.message } };
    if (this.reason !== undefined) body.error.reason = this.reason;
    return body;
  }
}

/** Headers added to every response. */
export const BASE_HEADERS: Readonly<Record<string, string>> = {
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
};

/** Options for {@link jsonResponse}. */
export interface JsonResponseInit {
  status?: number;
  headers?: HeadersInit;
}

/** Serialises `body` as a JSON response with no-store caching. */
export function jsonResponse(body: unknown, init: JsonResponseInit = {}): Response {
  const headers = new Headers(BASE_HEADERS);
  headers.set("content-type", "application/json; charset=utf-8");
  if (init.headers) new Headers(init.headers).forEach((value, key) => headers.set(key, value));
  return new Response(JSON.stringify(body), { status: init.status ?? 200, headers });
}

/** Builds an error response for `code` with an optional custom friendly message. */
export function errorResponse(
  code: ErrorCode,
  message?: string,
  options: Omit<HttpErrorOptions, "cause"> = {},
): Response {
  return httpErrorResponse(new HttpError(code, message, options));
}

/** Builds the response for an {@link HttpError}. */
export function httpErrorResponse(err: HttpError): Response {
  return jsonResponse(err.toBody(), { status: err.status, headers: err.headers });
}

/**
 * Converts anything thrown into a response. {@link HttpError}s keep their code; everything else
 * becomes a generic 500 so internal details never leak to the client.
 */
export function errorResponseFrom(err: unknown): Response {
  return httpErrorResponse(err instanceof HttpError ? err : new HttpError("internal"));
}

/** Throws `method_not_allowed` (with an `allow` header) unless the method is one of `methods`. */
export function assertMethod(req: Request, ...methods: string[]): void {
  if (!methods.includes(req.method)) {
    throw new HttpError("method_not_allowed", undefined, {
      headers: { allow: methods.join(", ") },
    });
  }
}

/** Default request body cap for {@link readJsonBody}. */
export const DEFAULT_MAX_BODY_BYTES = 64 * 1024;

/**
 * Reads and parses a JSON request body.
 *
 * Throws `too_long` when the body exceeds `maxBytes` (checked against `content-length` and while
 * streaming) and `invalid_request` for a content type other than JSON or `text/plain`, an empty
 * body, invalid UTF-8 or malformed JSON.
 */
export async function readJsonBody(
  req: Request,
  options: { maxBytes?: number } = {},
): Promise<unknown> {
  const maxBytes = options.maxBytes ?? DEFAULT_MAX_BODY_BYTES;
  const contentType = req.headers.get("content-type");
  // `text/plain` is accepted because some HTTP clients send it by default for string bodies.
  if (
    contentType !== null &&
    !/^(application\/([\w.+-]+\+)?json|text\/plain)\b/i.test(contentType.trim())
  ) {
    throw new HttpError("invalid_request");
  }
  const declared = Number(req.headers.get("content-length") ?? "NaN");
  if (Number.isFinite(declared) && declared > maxBytes) throw new HttpError("too_long");
  if (req.body === null) throw new HttpError("invalid_request");

  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) {
        await reader.cancel().catch(() => {});
        throw new HttpError("too_long");
      }
      chunks.push(value);
    }
  } catch (err) {
    if (err instanceof HttpError) throw err;
    throw new HttpError("invalid_request", undefined, { cause: err });
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch (err) {
    throw new HttpError("invalid_request", undefined, { cause: err });
  }
  if (text.trim() === "") throw new HttpError("invalid_request");
  try {
    return JSON.parse(text);
  } catch (err) {
    throw new HttpError("invalid_request", undefined, { cause: err });
  }
}

/** True for a plain JSON object (not null, not an array). */
export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// ---------------------------------------------------------------------------------------------
// Postgres / PostgREST error mapping
// ---------------------------------------------------------------------------------------------

/** Structural subset of a supabase-js `PostgrestError`. */
export interface PgErrorLike {
  code?: string | null;
  message?: string | null;
  details?: string | null;
  hint?: string | null;
}

const BUSINESS_KEY = /^[a-z][a-z0-9_]{1,63}$/;

/**
 * Returns the stable business-rule key of an RPC error raised with `errcode P0001`
 * (for example `quota_exceeded`), or `undefined` for any other error.
 */
export function pgErrorKey(err: PgErrorLike | null | undefined): string | undefined {
  if (!err || err.code !== "P0001") return undefined;
  const key = err.message?.trim();
  return key !== undefined && BUSINESS_KEY.test(key) ? key : undefined;
}

const PG_CODE_MAP: Readonly<Record<string, ErrorCode>> = {
  "42501": "forbidden", // insufficient_privilege
  "P0002": "not_found", // no_data_found
  "22023": "invalid_request", // invalid_parameter_value
  "22P02": "invalid_request", // invalid_text_representation
  "23514": "invalid_request", // check_violation
  "23502": "invalid_request", // not_null_violation
  "22001": "too_long", // string_data_right_truncation
  "23505": "conflict", // unique_violation
  "23503": "conflict", // foreign_key_violation
  "PGRST301": "unauthorized", // JWT expired / invalid
  "PGRST302": "unauthorized", // anonymous access disabled
};

/**
 * Maps a database/RPC error to an {@link HttpError}.
 *
 * - `P0001` business keys that equal an {@link ErrorCode} (`quota_exceeded`, `rate_limited`,
 *   `forbidden`, ...) use that code; `keyCodes` maps other keys (e.g. `{ invite_expired: "conflict" }`);
 *   unmapped keys become `conflict`. The key is always passed through as `reason`.
 * - Known SQLSTATEs map per {@link PG_CODE_MAP}; anything else becomes `internal`.
 */
export function httpErrorFromPg(
  err: PgErrorLike,
  keyCodes: Readonly<Record<string, ErrorCode>> = {},
): HttpError {
  const key = pgErrorKey(err);
  if (key !== undefined) {
    const code = Object.hasOwn(keyCodes, key) ? keyCodes[key] : isErrorCode(key) ? key : "conflict";
    return new HttpError(code, undefined, { reason: key, cause: err });
  }
  const mapped = err.code ? PG_CODE_MAP[err.code] : undefined;
  return new HttpError(mapped ?? "internal", undefined, { cause: err });
}
