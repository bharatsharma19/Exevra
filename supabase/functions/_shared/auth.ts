/**
 * Caller authentication and Supabase client factories.
 *
 * Handlers depend on the structural {@link AuthCapableClient} type and receive a factory, so tests
 * can pass a fake client instead of a real supabase-js instance.
 */
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.118.0";
import { HttpError } from "./http.ts";
import type { SupabaseAdminEnv, SupabaseEnv } from "./env.ts";

export type { SupabaseClient };

/** The parts of a Supabase auth user the functions rely on. */
export interface AuthUser {
  id: string;
  email?: string | null;
  email_confirmed_at?: string | null;
  app_metadata?: Record<string, unknown>;
}

/** Shape of `auth.getUser` results that the functions read. */
export interface GetUserResult {
  data: { user: AuthUser | null };
  error: { status?: number; name?: string } | null;
}

/** Any client (real or fake) exposing `auth.getUser(jwt)`. */
export interface AuthCapableClient {
  auth: { getUser(jwt?: string): Promise<GetUserResult> };
}

/** Builds a client that acts as the caller. Receives the full `Bearer <jwt>` header value. */
export type UserClientFactory<C> = (authorization: string) => C;

/** Result of {@link authenticate}. */
export interface AuthContext<C> {
  user: AuthUser;
  /** The raw JWT (never log it). */
  token: string;
  /** The `Bearer <jwt>` header value. */
  authorization: string;
  /** A client scoped to the caller, so RLS applies. */
  client: C;
}

const MAX_TOKEN_LENGTH = 8192;
const JWT_SHAPE = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$/;

/**
 * Extracts a JWT from the `Authorization: Bearer <jwt>` header. Returns `null` when the header is
 * missing, uses another scheme, or does not look like a JWT.
 */
export function bearerToken(source: Request | Headers): string | null {
  const headers = source instanceof Headers ? source : source.headers;
  const header = headers.get("authorization");
  if (header === null) return null;
  const match = /^Bearer[ \t]+(\S+)[ \t]*$/i.exec(header);
  if (match === null) return null;
  const token = match[1];
  return token.length <= MAX_TOKEN_LENGTH && JWT_SHAPE.test(token) ? token : null;
}

/** Shared supabase-js options for server-side clients: no session storage or refresh. */
const SERVER_AUTH_OPTIONS = {
  persistSession: false,
  autoRefreshToken: false,
  detectSessionInUrl: false,
} as const;

/** Creates a supabase-js client that sends the caller's `Authorization` header (RLS applies). */
export function createUserClient(env: SupabaseEnv, authorization: string): SupabaseClient {
  return createClient(env.url, env.anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: SERVER_AUTH_OPTIONS,
  });
}

/** Creates a service-role client (bypasses RLS). Use only for explicitly privileged steps. */
export function createAdminClient(env: SupabaseAdminEnv): SupabaseClient {
  return createClient(env.url, env.serviceRoleKey, { auth: SERVER_AUTH_OPTIONS });
}

/** Returns a {@link UserClientFactory} bound to `env`. */
export function userClientFactory(env: SupabaseEnv): UserClientFactory<SupabaseClient> {
  return (authorization) => createUserClient(env, authorization);
}

/**
 * Verifies the caller's JWT with `auth.getUser` and returns the user plus a caller-scoped client.
 *
 * Throws `HttpError("unauthorized")` for a missing, malformed, expired or revoked token, and
 * `HttpError("unavailable")` when the auth service cannot be reached (so the app retries instead
 * of signing the user out).
 */
export async function authenticate<C extends AuthCapableClient>(
  req: Request,
  makeClient: UserClientFactory<C>,
): Promise<AuthContext<C>> {
  const token = bearerToken(req);
  if (token === null) throw new HttpError("unauthorized");
  const authorization = `Bearer ${token}`;
  const client = makeClient(authorization);

  let result: GetUserResult;
  try {
    result = await client.auth.getUser(token);
  } catch (err) {
    throw new HttpError("unavailable", undefined, { cause: err });
  }

  const { data, error } = result;
  if (error) {
    const status = typeof error.status === "number" ? error.status : undefined;
    const transient = error.name === "AuthRetryableFetchError" || status === 0 ||
      (status !== undefined && status >= 500);
    throw new HttpError(transient ? "unavailable" : "unauthorized", undefined, { cause: error });
  }
  const user = data?.user;
  if (!user || typeof user.id !== "string" || user.id === "") {
    throw new HttpError("unauthorized");
  }
  return { user, token, authorization, client };
}
