/**
 * Typed environment reader.
 *
 * Every function reads configuration through an {@link EnvSource} so handlers can be tested with
 * a plain record instead of the process environment. Values are trimmed and empty strings count
 * as missing. Error messages only ever name variables, never their values.
 */

/** Looks up one environment variable. */
export type EnvSource = (name: string) => string | undefined;

/** Reads from the real process environment (needs `--allow-env` outside the Edge Runtime). */
export const denoEnv: EnvSource = (name: string): string | undefined => Deno.env.get(name);

/** Builds an {@link EnvSource} from a plain record, for tests and local tooling. */
export function envFromRecord(record: Readonly<Record<string, string | undefined>>): EnvSource {
  return (name) => (Object.hasOwn(record, name) ? record[name] : undefined);
}

/** Thrown when required configuration is missing or malformed. Lists names only. */
export class MissingEnvError extends Error {
  readonly names: readonly string[];

  constructor(names: readonly string[]) {
    super(`Missing or invalid environment variables: ${names.join(", ")}`);
    this.name = "MissingEnvError";
    this.names = [...names];
  }
}

/** Returns the trimmed value, or `undefined` when unset or blank. */
export function envString(env: EnvSource, name: string): string | undefined {
  const value = env(name)?.trim();
  return value ? value : undefined;
}

/** Returns the trimmed value or throws {@link MissingEnvError}. */
export function envRequired(env: EnvSource, name: string): string {
  const value = envString(env, name);
  if (value === undefined) throw new MissingEnvError([name]);
  return value;
}

/** Options for {@link envInt}. */
export interface EnvIntOptions {
  /** Used when the variable is unset or not an integer. */
  fallback: number;
  /** Inclusive lower bound; smaller values are clamped. */
  min?: number;
  /** Inclusive upper bound; larger values are clamped. */
  max?: number;
}

/** Reads a base-10 integer, falling back on unset or malformed values and clamping to bounds. */
export function envInt(env: EnvSource, name: string, options: EnvIntOptions): number {
  const raw = envString(env, name);
  let value = raw !== undefined && /^-?\d{1,15}$/.test(raw) ? Number(raw) : options.fallback;
  if (options.min !== undefined && value < options.min) value = options.min;
  if (options.max !== undefined && value > options.max) value = options.max;
  return value;
}

const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1", "[::1]"]);

/**
 * Parses a base URL. Requires `https:` (plain `http:` is accepted only for localhost), rejects
 * credentials, query strings and fragments, and strips trailing slashes.
 * Returns `undefined` when unset or invalid.
 */
export function envBaseUrl(env: EnvSource, name: string): string | undefined {
  const raw = envString(env, name);
  if (raw === undefined) return undefined;
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return undefined;
  }
  const secure = url.protocol === "https:" ||
    (url.protocol === "http:" && LOCAL_HOSTS.has(url.hostname));
  if (!secure || url.username || url.password || url.search || url.hash) return undefined;
  return `${url.origin}${url.pathname}`.replace(/\/+$/, "");
}

// ---------------------------------------------------------------------------------------------
// Supabase platform values (injected by the Edge Runtime, never stored in .env files).
// ---------------------------------------------------------------------------------------------

/** Values needed for a caller-scoped (RLS) client. */
export interface SupabaseEnv {
  url: string;
  anonKey: string;
}

/** Values needed for a service-role client. */
export interface SupabaseAdminEnv extends SupabaseEnv {
  serviceRoleKey: string;
}

/** Reads `SUPABASE_URL` and `SUPABASE_ANON_KEY`. Throws {@link MissingEnvError}. */
export function readSupabaseEnv(env: EnvSource = denoEnv): SupabaseEnv {
  const missing: string[] = [];
  // Locally the runtime injects an internal http URL (e.g. http://kong:8000), so plain http is
  // allowed here; the value comes from the platform, not from users.
  const rawUrl = envString(env, "SUPABASE_URL");
  const url = rawUrl !== undefined && /^https?:\/\/[^\s/]+/.test(rawUrl)
    ? rawUrl.replace(/\/+$/, "")
    : undefined;
  if (url === undefined) missing.push("SUPABASE_URL");
  const anonKey = envString(env, "SUPABASE_ANON_KEY");
  if (anonKey === undefined) missing.push("SUPABASE_ANON_KEY");
  if (missing.length > 0 || url === undefined || anonKey === undefined) {
    throw new MissingEnvError(missing);
  }
  return { url, anonKey };
}

/** Reads the {@link SupabaseEnv} values plus `SUPABASE_SERVICE_ROLE_KEY`. */
export function readSupabaseAdminEnv(env: EnvSource = denoEnv): SupabaseAdminEnv {
  const missing: string[] = [];
  let base: SupabaseEnv | undefined;
  try {
    base = readSupabaseEnv(env);
  } catch (err) {
    if (!(err instanceof MissingEnvError)) throw err;
    missing.push(...err.names);
  }
  const serviceRoleKey = envString(env, "SUPABASE_SERVICE_ROLE_KEY");
  if (serviceRoleKey === undefined) missing.push("SUPABASE_SERVICE_ROLE_KEY");
  if (missing.length > 0 || base === undefined || serviceRoleKey === undefined) {
    throw new MissingEnvError(missing);
  }
  return { ...base, serviceRoleKey };
}

// ---------------------------------------------------------------------------------------------
// ai-chat
// ---------------------------------------------------------------------------------------------

export const DEFAULT_CLAUDE_MODEL = "claude-haiku-5-5";
export const DEFAULT_GEMINI_MODEL = "gemini-3.8-flash";
export const DEFAULT_AI_DAILY_QUOTA = 50;
export const DEFAULT_AI_PER_MINUTE = 6;

/** ai-chat configuration. A provider is usable only when its key is present. */
export interface AiEnv {
  anthropicApiKey?: string;
  geminiApiKey?: string;
  claudeModel: string;
  geminiModel: string;
  /** Requests per user per UTC day, 1..1000. */
  dailyQuota: number;
  /** Requests per user per rolling minute, 1..60. */
  perMinute: number;
}

/** Reads ai-chat settings. Never throws: missing keys simply disable that provider. */
export function readAiEnv(env: EnvSource = denoEnv): AiEnv {
  return {
    anthropicApiKey: envString(env, "ANTHROPIC_API_KEY"),
    geminiApiKey: envString(env, "GEMINI_API_KEY"),
    claudeModel: envString(env, "CLAUDE_MODEL") ?? DEFAULT_CLAUDE_MODEL,
    geminiModel: envString(env, "GEMINI_MODEL") ?? DEFAULT_GEMINI_MODEL,
    dailyQuota: envInt(env, "AI_DAILY_QUOTA", {
      fallback: DEFAULT_AI_DAILY_QUOTA,
      min: 1,
      max: 1000,
    }),
    perMinute: envInt(env, "AI_PER_MINUTE", { fallback: DEFAULT_AI_PER_MINUTE, min: 1, max: 60 }),
  };
}

// ---------------------------------------------------------------------------------------------
// send-invite
// ---------------------------------------------------------------------------------------------

/** Email delivery configuration for invitations. */
export interface InviteEnv {
  resendApiKey: string;
  /** RFC 5322 sender, e.g. `Exevra <invites@example.com>`. */
  fromEmail: string;
  /** Base URL for invitation links, without a trailing slash. */
  appBaseUrl: string;
}

/** Reads `RESEND_API_KEY`, `INVITE_FROM_EMAIL` and `APP_BASE_URL`. Throws {@link MissingEnvError}. */
export function readInviteEnv(env: EnvSource = denoEnv): InviteEnv {
  const missing: string[] = [];
  const resendApiKey = envString(env, "RESEND_API_KEY");
  if (resendApiKey === undefined) missing.push("RESEND_API_KEY");
  const fromRaw = envString(env, "INVITE_FROM_EMAIL");
  const fromEmail = fromRaw !== undefined && fromRaw.includes("@") && !/[\r\n]/.test(fromRaw)
    ? fromRaw
    : undefined;
  if (fromEmail === undefined) missing.push("INVITE_FROM_EMAIL");
  const appBaseUrl = envBaseUrl(env, "APP_BASE_URL");
  if (appBaseUrl === undefined) missing.push("APP_BASE_URL");
  if (
    missing.length > 0 || resendApiKey === undefined || fromEmail === undefined ||
    appBaseUrl === undefined
  ) {
    throw new MissingEnvError(missing);
  }
  return { resendApiKey, fromEmail, appBaseUrl };
}

// ---------------------------------------------------------------------------------------------
// delete-account (Sign in with Apple token revocation)
// ---------------------------------------------------------------------------------------------

/** Credentials for Apple's token revocation endpoint. */
export interface AppleEnv {
  teamId: string;
  keyId: string;
  /** The Services ID / bundle ID used as `client_id`. */
  clientId: string;
  /** PKCS#8 PEM. Escaped `\n` sequences are turned into real newlines. */
  privateKey: string;
}

const APPLE_VARS = ["APPLE_TEAM_ID", "APPLE_KEY_ID", "APPLE_CLIENT_ID", "APPLE_PRIVATE_KEY"];

/**
 * Reads Apple credentials. Returns `null` when none are set (Apple sign-in not configured) and
 * throws {@link MissingEnvError} when only some are set.
 */
export function readAppleEnv(env: EnvSource = denoEnv): AppleEnv | null {
  const values = APPLE_VARS.map((name) => envString(env, name));
  const missing = APPLE_VARS.filter((_, i) => values[i] === undefined);
  if (missing.length === APPLE_VARS.length) return null;
  const [teamId, keyId, clientId, privateKey] = values;
  if (
    missing.length > 0 || teamId === undefined || keyId === undefined ||
    clientId === undefined || privateKey === undefined
  ) {
    throw new MissingEnvError(missing);
  }
  return { teamId, keyId, clientId, privateKey: privateKey.replace(/\\n/g, "\n") };
}
