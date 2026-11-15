import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.19";
import {
  DEFAULT_CLAUDE_MODEL,
  DEFAULT_GEMINI_MODEL,
  envBaseUrl,
  envFromRecord,
  envInt,
  envRequired,
  envString,
  MissingEnvError,
  readAiEnv,
  readAppleEnv,
  readInviteEnv,
  readSupabaseAdminEnv,
  readSupabaseEnv,
} from "./env.ts";

Deno.test("envString trims and treats blank as missing", () => {
  const env = envFromRecord({ A: "  x  ", B: "   ", C: "" });
  assertEquals(envString(env, "A"), "x");
  assertEquals(envString(env, "B"), undefined);
  assertEquals(envString(env, "C"), undefined);
  assertEquals(envString(env, "D"), undefined);
});

Deno.test("envFromRecord ignores prototype keys", () => {
  assertEquals(envString(envFromRecord({}), "toString"), undefined);
});

Deno.test("envRequired throws MissingEnvError naming the variable only", () => {
  const err = assertThrows(() => envRequired(envFromRecord({}), "SECRET_THING"), MissingEnvError);
  assertEquals(err.names, ["SECRET_THING"]);
});

Deno.test("envInt falls back on garbage and clamps", () => {
  const env = envFromRecord({ OK: "12", BAD: "12abc", BIG: "99999", NEG: "-5", FLOAT: "1.5" });
  assertEquals(envInt(env, "OK", { fallback: 3 }), 12);
  assertEquals(envInt(env, "BAD", { fallback: 3 }), 3);
  assertEquals(envInt(env, "FLOAT", { fallback: 3 }), 3);
  assertEquals(envInt(env, "MISSING", { fallback: 3 }), 3);
  assertEquals(envInt(env, "BIG", { fallback: 3, max: 100 }), 100);
  assertEquals(envInt(env, "NEG", { fallback: 3, min: 1 }), 1);
});

Deno.test("envBaseUrl requires https except on localhost", () => {
  const env = envFromRecord({
    A: "https://exevra.app/",
    B: "https://exevra.app/invite//",
    C: "http://exevra.app",
    D: "http://localhost:3000/",
    E: "https://user:pw@exevra.app",
    F: "https://exevra.app/?x=1",
    G: "javascript:alert(1)",
    H: "not a url",
  });
  assertEquals(envBaseUrl(env, "A"), "https://exevra.app");
  assertEquals(envBaseUrl(env, "B"), "https://exevra.app/invite");
  assertEquals(envBaseUrl(env, "C"), undefined);
  assertEquals(envBaseUrl(env, "D"), "http://localhost:3000");
  assertEquals(envBaseUrl(env, "E"), undefined);
  assertEquals(envBaseUrl(env, "F"), undefined);
  assertEquals(envBaseUrl(env, "G"), undefined);
  assertEquals(envBaseUrl(env, "H"), undefined);
});

Deno.test("readSupabaseEnv reads platform values and lists all missing names", () => {
  assertEquals(
    readSupabaseEnv(envFromRecord({ SUPABASE_URL: "http://kong:8000/", SUPABASE_ANON_KEY: "a" })),
    { url: "http://kong:8000", anonKey: "a" },
  );
  const err = assertThrows(() => readSupabaseAdminEnv(envFromRecord({})), MissingEnvError);
  assertEquals(err.names, ["SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY"]);
  assertEquals(
    readSupabaseAdminEnv(
      envFromRecord({
        SUPABASE_URL: "https://x.supabase.co",
        SUPABASE_ANON_KEY: "a",
        SUPABASE_SERVICE_ROLE_KEY: "s",
      }),
    ),
    { url: "https://x.supabase.co", anonKey: "a", serviceRoleKey: "s" },
  );
});

Deno.test("readAiEnv applies defaults and bounds", () => {
  assertEquals(readAiEnv(envFromRecord({})), {
    anthropicApiKey: undefined,
    geminiApiKey: undefined,
    claudeModel: DEFAULT_CLAUDE_MODEL,
    geminiModel: DEFAULT_GEMINI_MODEL,
    dailyQuota: 20,
    perMinute: 4,
  });
  const env = readAiEnv(
    envFromRecord({
      ANTHROPIC_API_KEY: "k1",
      GEMINI_API_KEY: "k2",
      CLAUDE_MODEL: "claude-sonnet-5-5",
      AI_DAILY_QUOTA: "0",
      AI_PER_MINUTE: "1000",
    }),
  );
  assertEquals(env.claudeModel, "claude-sonnet-5-5");
  assertEquals(env.anthropicApiKey, "k1");
  assertEquals(env.dailyQuota, 1);
  assertEquals(env.perMinute, 60);
});

Deno.test("readInviteEnv validates sender and base url", () => {
  assertEquals(
    readInviteEnv(
      envFromRecord({
        RESEND_API_KEY: "r",
        INVITE_FROM_EMAIL: "Exevra <invites@example.com>",
        APP_BASE_URL: "https://example.com/",
      }),
    ),
    {
      resendApiKey: "r",
      fromEmail: "Exevra <invites@example.com>",
      appBaseUrl: "https://example.com",
    },
  );
  const err = assertThrows(
    () =>
      readInviteEnv(
        envFromRecord({ INVITE_FROM_EMAIL: "no-at-sign", APP_BASE_URL: "http://example.com" }),
      ),
    MissingEnvError,
  );
  assertEquals(err.names, ["RESEND_API_KEY", "INVITE_FROM_EMAIL", "APP_BASE_URL"]);
});

Deno.test("readAppleEnv is null when unconfigured and strict when partial", () => {
  assertEquals(readAppleEnv(envFromRecord({})), null);
  const err = assertThrows(
    () => readAppleEnv(envFromRecord({ APPLE_TEAM_ID: "T" })),
    MissingEnvError,
  );
  assertEquals(err.names, ["APPLE_KEY_ID", "APPLE_CLIENT_ID", "APPLE_PRIVATE_KEY"]);
  const apple = readAppleEnv(
    envFromRecord({
      APPLE_TEAM_ID: "T",
      APPLE_KEY_ID: "K",
      APPLE_CLIENT_ID: "C",
      APPLE_PRIVATE_KEY: "-----BEGIN PRIVATE KEY-----\\nabc\\n-----END PRIVATE KEY-----",
    }),
  );
  assertEquals(apple?.privateKey, "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----");
});
