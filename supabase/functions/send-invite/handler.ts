/**
 * send-invite: creates a group invitation as the caller and emails the link.
 *
 * Flow: verify JWT -> validate input -> `create_group_invitation` (admin check, rate limits and
 * the 256-bit token all live in the database) -> read group and inviter names -> render the
 * email -> send through Resend. The invitation exists once the RPC succeeds, so email problems
 * return 200 with `sent: false` and a `share_url` the app can offer for manual sharing. The
 * response never claims an email was sent unless Resend answered 2xx.
 */
import { authenticate, type UserClientFactory } from "../_shared/auth.ts";
import { type Clock, systemClock } from "../_shared/clock.ts";
import { envBaseUrl, type EnvSource, MissingEnvError, readInviteEnv } from "../_shared/env.ts";
import {
  assertMethod,
  type ErrorCode,
  errorResponseFrom,
  HttpError,
  httpErrorFromPg,
  isRecord,
  jsonResponse,
  type PgErrorLike,
  readJsonBody,
} from "../_shared/http.ts";
import { errorName, type Logger, newRequestId, silentLogger } from "../_shared/log.ts";
import type { InviteDb, InviteRole } from "./db.ts";
import { renderInviteEmail } from "./email.ts";
import { type FetchFn, sendWithResend } from "./resend.ts";

/** Dependencies injected by `index.ts` (real) or tests (fakes). */
export interface SendInviteDeps {
  env: EnvSource;
  makeClient: UserClientFactory<InviteDb>;
  fetchFn?: FetchFn;
  clock?: Clock;
  logger?: Logger;
  requestId?: () => string;
}

/** Validated request body. */
export interface InviteRequest {
  groupId: string;
  email: string;
  role: InviteRole;
}

/** Successful response body. */
export interface InviteResponse {
  invitation_id: string;
  sent: boolean;
  expires_at: string | null;
  reason?: "email_not_configured" | "email_failed";
  share_url?: string;
}

const MAX_BODY_BYTES = 4096;
const MAX_EMAIL_LENGTH = 254;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** Same rule as the database check on group_invitations.email (applied after lower-casing). */
const EMAIL = /^[a-z0-9._%+'-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$/;
/** base64url, as produced by create_group_invitation (32 random bytes -> 43 chars). */
const TOKEN = /^[A-Za-z0-9_-]{16,256}$/;
const DAY_MS = 86_400_000;
const DEFAULT_EXPIRY_DAYS = 7;

/** Friendly copy for database business keys the app may show. */
const REASON_MESSAGES: Readonly<
  Record<string, { code: ErrorCode; message: string }>
> = {
  not_group_admin: {
    code: "forbidden",
    message: "Only group admins can invite people.",
  },
  not_authenticated: {
    code: "unauthorized",
    message: "Your session has expired. Please sign in again.",
  },
  group_not_found: {
    code: "not_found",
    message: "We couldn't find that group.",
  },
  already_member: {
    code: "conflict",
    message: "That person is already in this group.",
  },
  invalid_email: {
    code: "invalid_request",
    message: "Please enter a valid email address.",
  },
  invalid_role: {
    code: "invalid_request",
    message: "Choose either member or viewer.",
  },
  rate_limited: {
    code: "rate_limited",
    message: "You've sent a lot of invitations recently. Please try again later.",
  },
};

/** Validates and normalises the JSON body. Throws `invalid_request` with friendly copy. */
export function parseInviteRequest(body: unknown): InviteRequest {
  if (!isRecord(body)) throw new HttpError("invalid_request");
  const { group_id: groupId, email: rawEmail, role: rawRole } = body;
  if (typeof groupId !== "string" || !UUID.test(groupId)) {
    throw new HttpError(
      "invalid_request",
      "That group couldn't be found. Please try again.",
    );
  }
  const email = typeof rawEmail === "string" ? rawEmail.trim().toLowerCase() : "";
  if (
    email.length === 0 || email.length > MAX_EMAIL_LENGTH || !EMAIL.test(email)
  ) {
    throw new HttpError(
      "invalid_request",
      "Please enter a valid email address.",
      {
        reason: "invalid_email",
      },
    );
  }
  const role = rawRole === undefined || rawRole === null ? "member" : rawRole;
  if (role !== "member" && role !== "viewer") {
    throw new HttpError("invalid_request", "Choose either member or viewer.", {
      reason: "invalid_role",
    });
  }
  return { groupId: groupId.toLowerCase(), email, role };
}

/** Maps a `create_group_invitation` error to a friendly {@link HttpError}. */
export function mapInvitationError(err: PgErrorLike): HttpError {
  const key = err.message?.trim() ?? "";
  const known = Object.hasOwn(REASON_MESSAGES, key) ? REASON_MESSAGES[key] : undefined;
  if (known !== undefined) {
    return new HttpError(known.code, known.message, {
      reason: key,
      cause: err,
    });
  }
  return httpErrorFromPg(err);
}

/** Builds `${APP_BASE_URL}/invite/<token>`. The base always comes from the environment. */
export function buildInviteLink(appBaseUrl: string, token: string): string {
  return `${appBaseUrl}/invite/${encodeURIComponent(token)}`;
}

function daysUntil(expiresAt: string | null, now: number): number {
  const ms = expiresAt === null ? Number.NaN : Date.parse(expiresAt);
  return Number.isFinite(ms) ? Math.max(1, Math.round((ms - now) / DAY_MS)) : DEFAULT_EXPIRY_DAYS;
}

/** Creates the request handler. */
export function createSendInviteHandler(
  deps: SendInviteDeps,
): (req: Request) => Promise<Response> {
  const clock = deps.clock ?? systemClock;
  const logger = deps.logger ?? silentLogger;
  const nextRequestId = deps.requestId ?? newRequestId;

  return async (req: Request): Promise<Response> => {
    const requestId = nextRequestId();
    const started = clock.now();
    const log = (
      fields: Record<string, string | number | boolean | undefined>,
    ): void => {
      logger.info({
        request_id: requestId,
        latency_ms: clock.now() - started,
        ...fields,
      });
    };

    try {
      assertMethod(req, "POST");
      const { user, client } = await authenticate(req, deps.makeClient);
      const input = parseInviteRequest(
        await readJsonBody(req, { maxBytes: MAX_BODY_BYTES }),
      );

      // The link base is fixed by configuration and never taken from the request.
      const appBaseUrl = envBaseUrl(deps.env, "APP_BASE_URL");
      if (appBaseUrl === undefined) {
        throw new HttpError(
          "unavailable",
          "Invitations aren't available right now.",
          {
            cause: new MissingEnvError(["APP_BASE_URL"]),
          },
        );
      }

      const created = await client.createInvitation(
        input.groupId,
        input.email,
        input.role,
      );
      if (created.error !== null) throw mapInvitationError(created.error);
      const invitation = created.data;
      if (!TOKEN.test(invitation.token)) throw new HttpError("internal");
      const link = buildInviteLink(appBaseUrl, invitation.token);

      const base: InviteResponse = {
        invitation_id: invitation.invitationId,
        sent: false,
        expires_at: invitation.expiresAt,
      };

      let mail: { resendApiKey: string; fromEmail: string } | null = null;
      try {
        mail = readInviteEnv(deps.env);
      } catch (err) {
        if (!(err instanceof MissingEnvError)) throw err;
      }
      if (mail === null) {
        log({ status: "not_sent", reason: "email_not_configured" });
        return jsonResponse({
          ...base,
          reason: "email_not_configured",
          share_url: link,
        });
      }

      const [groupName, inviterName] = await Promise.all([
        client.getGroupName(input.groupId),
        client.getDisplayName(user.id),
      ]);
      const email = renderInviteEmail({
        inviterName,
        groupName,
        role: input.role,
        recipientEmail: input.email,
        link,
        expiresInDays: daysUntil(invitation.expiresAt, clock.now()),
      });

      const result = await sendWithResend(mail.resendApiKey, {
        from: mail.fromEmail,
        to: input.email,
        subject: email.subject,
        html: email.html,
        text: email.text,
        idempotencyKey: invitation.invitationId,
      }, { fetchFn: deps.fetchFn });

      if (!result.ok) {
        logger.warn({
          request_id: requestId,
          latency_ms: clock.now() - started,
          status: "not_sent",
          reason: "email_failed",
          provider_status: result.status,
          error: result.error,
        });
        return jsonResponse({
          ...base,
          reason: "email_failed",
          share_url: link,
        });
      }
      log({ status: "sent", provider_status: result.status });
      return jsonResponse({ ...base, sent: true });
    } catch (err) {
      const httpErr = err instanceof HttpError ? err : undefined;
      const fields = {
        request_id: requestId,
        latency_ms: clock.now() - started,
        status: "error",
        code: httpErr?.code ?? "internal",
        reason: httpErr?.reason,
        error: errorName(httpErr?.cause ?? err),
      };
      if (httpErr === undefined || httpErr.status >= 500) logger.error(fields);
      else logger.info(fields);
      return errorResponseFrom(err);
    }
  };
}
