/**
 * delete-account: permanently deletes the caller's account.
 *
 * Flow: verify JWT -> service-role `prepare_account_deletion(p_user_id)` (hands group admin on,
 * anonymises shared history as "Former member", deletes personal data) -> revoke Sign in with
 * Apple tokens when possible (never blocks deletion) -> `auth.admin.deleteUser`.
 *
 * Every step is idempotent, so the app can safely retry. Any failure before the auth user is
 * deleted returns 500 `deletion_failed`; the app must then keep the user signed in and offer a
 * retry instead of behaving as if the account were gone.
 */
import {
  type AuthCapableClient,
  authenticate,
  type AuthUser,
  type UserClientFactory,
} from "../_shared/auth.ts";
import { type Clock, systemClock } from "../_shared/clock.ts";
import { type EnvSource, readAppleEnv } from "../_shared/env.ts";
import {
  assertMethod,
  errorResponseFrom,
  HttpError,
  isRecord,
  jsonResponse,
} from "../_shared/http.ts";
import { errorName, type Logger, newRequestId, silentLogger } from "../_shared/log.ts";
import { type AccountAdmin, isUserNotFound } from "./admin.ts";
import { type FetchFn, isAppleAuthorizationCode, revokeAppleTokens } from "./apple.ts";

/** Dependencies injected by `index.ts` (real) or tests (fakes). */
export interface DeleteAccountDeps {
  env: EnvSource;
  makeUserClient: UserClientFactory<AuthCapableClient>;
  /** Builds the service-role port. May throw when configuration is missing. */
  makeAdmin: () => AccountAdmin;
  fetchFn?: FetchFn;
  clock?: Clock;
  logger?: Logger;
  requestId?: () => string;
}

/** Successful response body. */
export interface DeleteAccountResponse {
  deleted: true;
  apple_revoked: boolean;
}

/** Error code returned when the account could not be deleted. */
export const DELETION_FAILED = "deletion_failed";
export const DELETION_FAILED_MESSAGE =
  "We couldn't delete your account right now. Nothing was signed out. Please try again.";

const MAX_BODY_BYTES = 8192;

/** Apple outcome, for logs only. */
type AppleOutcome =
  | "not_linked"
  | "no_code"
  | "not_configured"
  | "misconfigured"
  | "revoked"
  | "client_secret_failed"
  | "token_exchange_failed"
  | "no_token"
  | "revoke_failed";

class DeletionFailed extends Error {
  readonly stage: string;
  constructor(stage: string, options?: { cause?: unknown }) {
    super("deletion_failed", options);
    this.name = "DeletionFailed";
    this.stage = stage;
  }
}

function deletionFailedResponse(): Response {
  return jsonResponse(
    { error: { code: DELETION_FAILED, message: DELETION_FAILED_MESSAGE } },
    { status: 500 },
  );
}

/** True when the user signed in with Apple (identity list or provider metadata). */
export function hasAppleIdentity(user: AuthUser): boolean {
  const meta = user.app_metadata;
  if (meta?.provider === "apple") return true;
  if (Array.isArray(meta?.providers) && meta.providers.includes("apple")) return true;
  const identities = (user as { identities?: unknown }).identities;
  return Array.isArray(identities) &&
    identities.some((identity) => isRecord(identity) && identity.provider === "apple");
}

/** Reads an optional small JSON object body. Empty bodies yield `{}`. */
export async function readOptionalJsonObject(
  req: Request,
  maxBytes = MAX_BODY_BYTES,
): Promise<Record<string, unknown>> {
  const declared = Number(req.headers.get("content-length") ?? "NaN");
  if (Number.isFinite(declared) && declared > maxBytes) throw new HttpError("too_long");
  if (req.body === null) return {};

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
  if (text.trim() === "") return {};
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch (err) {
    throw new HttpError("invalid_request", undefined, { cause: err });
  }
  if (!isRecord(parsed)) throw new HttpError("invalid_request");
  return parsed;
}

/** Creates the request handler. */
export function createDeleteAccountHandler(
  deps: DeleteAccountDeps,
): (req: Request) => Promise<Response> {
  const clock = deps.clock ?? systemClock;
  const logger = deps.logger ?? silentLogger;
  const nextRequestId = deps.requestId ?? newRequestId;

  return async (req: Request): Promise<Response> => {
    const requestId = nextRequestId();
    const started = clock.now();
    const elapsed = (): number => clock.now() - started;

    try {
      assertMethod(req, "POST");

      let user: AuthUser;
      try {
        ({ user } = await authenticate(req, deps.makeUserClient));
      } catch (err) {
        // A validly signed token whose user no longer exists: a retry after a deletion whose
        // response was lost. Report success so the app can finish signing out.
        if (
          err instanceof HttpError && err.code === "unauthorized" && isRecord(err.cause) &&
          err.cause.code === "user_not_found"
        ) {
          logger.info({ request_id: requestId, latency_ms: elapsed(), status: "already_deleted" });
          return jsonResponse({ deleted: true, apple_revoked: false });
        }
        if (err instanceof HttpError && err.code === "unauthorized") throw err;
        throw new DeletionFailed("authenticate", { cause: err });
      }

      const body = await readOptionalJsonObject(req);
      const rawCode = body.apple_authorization_code;
      if (rawCode !== undefined && rawCode !== null && !isAppleAuthorizationCode(rawCode)) {
        throw new HttpError("invalid_request");
      }
      const appleCode = typeof rawCode === "string" ? rawCode : null;

      let admin: AccountAdmin;
      try {
        admin = deps.makeAdmin();
      } catch (err) {
        throw new DeletionFailed("config", { cause: err });
      }

      const prepared = await admin.prepareAccountDeletion(user.id);
      if (prepared.error) {
        throw new DeletionFailed("prepare", { cause: prepared.error });
      }

      let apple: AppleOutcome = "not_linked";
      let appleStatus: number | undefined;
      if (hasAppleIdentity(user)) {
        apple = "no_code";
        if (appleCode !== null) {
          let appleEnv = null;
          try {
            appleEnv = readAppleEnv(deps.env);
            apple = appleEnv === null ? "not_configured" : apple;
          } catch {
            apple = "misconfigured";
          }
          if (appleEnv !== null) {
            const result = await revokeAppleTokens(appleEnv, appleCode, {
              nowMs: clock.now(),
              fetchFn: deps.fetchFn,
            });
            if (result.revoked) {
              apple = "revoked";
            } else {
              apple = result.failure;
              appleStatus = result.status;
            }
          }
        }
      }
      const appleRevoked = apple === "revoked";
      if (apple !== "revoked" && apple !== "not_linked") {
        logger.warn({
          request_id: requestId,
          stage: "apple_revoke",
          apple,
          provider_status: appleStatus,
        });
      }

      const deleted = await admin.deleteUser(user.id);
      const alreadyGone = isUserNotFound(deleted.error);
      if (deleted.error && !alreadyGone) {
        throw new DeletionFailed("delete_user", { cause: deleted.error });
      }

      logger.info({
        request_id: requestId,
        latency_ms: elapsed(),
        status: alreadyGone ? "already_deleted" : "deleted",
        apple,
      });
      const response: DeleteAccountResponse = { deleted: true, apple_revoked: appleRevoked };
      return jsonResponse(response);
    } catch (err) {
      if (err instanceof DeletionFailed) {
        const cause = err.cause;
        logger.error({
          request_id: requestId,
          latency_ms: elapsed(),
          status: "failed",
          stage: err.stage,
          code: isRecord(cause) && typeof cause.code === "string" ? cause.code : undefined,
          error: errorName(cause),
        });
        return deletionFailedResponse();
      }
      if (err instanceof HttpError) {
        logger.info({
          request_id: requestId,
          latency_ms: elapsed(),
          status: "rejected",
          code: err.code,
        });
        return errorResponseFrom(err);
      }
      logger.error({
        request_id: requestId,
        latency_ms: elapsed(),
        status: "failed",
        stage: "unexpected",
        error: errorName(err),
      });
      return deletionFailedResponse();
    }
  };
}
