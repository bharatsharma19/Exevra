/**
 * Sign in with Apple token revocation, required by App Store guideline 5.1.1(v) when an account
 * created with Apple is deleted.
 *
 * Supabase does not keep Apple's refresh token, so the app sends a fresh authorization code
 * (from re-authenticating with Apple just before deletion). We exchange it for a refresh token
 * and revoke that. See https://developer.apple.com/documentation/sign_in_with_apple/revoke_tokens
 */
import { importPKCS8, SignJWT } from "npm:jose@6.2.13";
import type { AppleEnv } from "../_shared/env.ts";
import { isRecord } from "../_shared/http.ts";

export const APPLE_AUDIENCE = "https://appleid.apple.com";
export const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
export const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";
/** Lifetime of the client secret JWT. Apple allows up to six months; we only need minutes. */
export const CLIENT_SECRET_TTL_SECONDS = 300;
export const APPLE_TIMEOUT_MS = 10_000;

/** Shape of Apple authorization codes (short-lived, single use). */
const AUTH_CODE = /^[A-Za-z0-9._-]{1,1024}$/;

/** True when `value` looks like an Apple authorization code. */
export function isAppleAuthorizationCode(value: unknown): value is string {
  return typeof value === "string" && AUTH_CODE.test(value);
}

/** A `fetch`-compatible function. */
export type FetchFn = (input: string, init: RequestInit) => Promise<Response>;

const globalFetch: FetchFn = (input: string, init: RequestInit): Promise<Response> =>
  fetch(input, init);

/** Why a revocation did not happen. Safe to log. */
export type AppleRevokeFailure =
  | "client_secret_failed"
  | "token_exchange_failed"
  | "no_token"
  | "revoke_failed";

/** Outcome of {@link revokeAppleTokens}. */
export type AppleRevokeResult =
  | { revoked: true }
  | { revoked: false; failure: AppleRevokeFailure; status?: number };

/** Creates the ES256 `client_secret` JWT Apple expects (header `kid`, iss=team, sub=client). */
export async function createAppleClientSecret(apple: AppleEnv, nowMs: number): Promise<string> {
  const key = await importPKCS8(apple.privateKey, "ES256");
  const iat = Math.floor(nowMs / 1000);
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: apple.keyId })
    .setIssuer(apple.teamId)
    .setSubject(apple.clientId)
    .setAudience(APPLE_AUDIENCE)
    .setIssuedAt(iat)
    .setExpirationTime(iat + CLIENT_SECRET_TTL_SECONDS)
    .sign(key);
}

async function postForm(
  fetchFn: FetchFn,
  url: string,
  form: Record<string, string>,
  timeoutMs: number,
): Promise<Response> {
  return await fetchFn(url, {
    method: "POST",
    headers: {
      "content-type": "application/x-www-form-urlencoded",
      "accept": "application/json",
    },
    body: new URLSearchParams(form).toString(),
    signal: AbortSignal.timeout(timeoutMs),
  });
}

/**
 * Exchanges `authorizationCode` for tokens and revokes the refresh token (or the access token
 * if Apple returned no refresh token). Never throws: failures are returned so deletion can go
 * ahead regardless.
 */
export async function revokeAppleTokens(
  apple: AppleEnv,
  authorizationCode: string,
  options: { nowMs: number; fetchFn?: FetchFn; timeoutMs?: number },
): Promise<AppleRevokeResult> {
  const fetchFn = options.fetchFn ?? globalFetch;
  const timeoutMs = options.timeoutMs ?? APPLE_TIMEOUT_MS;

  let clientSecret: string;
  try {
    clientSecret = await createAppleClientSecret(apple, options.nowMs);
  } catch {
    return { revoked: false, failure: "client_secret_failed" };
  }

  let token: string;
  let tokenTypeHint: "refresh_token" | "access_token";
  try {
    const res = await postForm(fetchFn, APPLE_TOKEN_URL, {
      client_id: apple.clientId,
      client_secret: clientSecret,
      code: authorizationCode,
      grant_type: "authorization_code",
    }, timeoutMs);
    if (!res.ok) {
      await res.body?.cancel().catch(() => {});
      return { revoked: false, failure: "token_exchange_failed", status: res.status };
    }
    const body: unknown = await res.json();
    const refresh = isRecord(body) ? body.refresh_token : undefined;
    const access = isRecord(body) ? body.access_token : undefined;
    if (typeof refresh === "string" && refresh !== "") {
      token = refresh;
      tokenTypeHint = "refresh_token";
    } else if (typeof access === "string" && access !== "") {
      token = access;
      tokenTypeHint = "access_token";
    } else {
      return { revoked: false, failure: "no_token" };
    }
  } catch {
    return { revoked: false, failure: "token_exchange_failed", status: 0 };
  }

  try {
    const res = await postForm(fetchFn, APPLE_REVOKE_URL, {
      client_id: apple.clientId,
      client_secret: clientSecret,
      token,
      token_type_hint: tokenTypeHint,
    }, timeoutMs);
    await res.body?.cancel().catch(() => {});
    return res.ok
      ? { revoked: true }
      : { revoked: false, failure: "revoke_failed", status: res.status };
  } catch {
    return { revoked: false, failure: "revoke_failed", status: 0 };
  }
}
