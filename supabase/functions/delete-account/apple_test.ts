import { assertEquals } from "jsr:@std/assert@1.0.19";
import { decodeProtectedHeader, jwtVerify } from "npm:jose@6.2.13";
import type { AppleEnv } from "../_shared/env.ts";
import { mockFetch } from "../_shared/testing.ts";
import {
  APPLE_REVOKE_URL,
  APPLE_TOKEN_URL,
  createAppleClientSecret,
  isAppleAuthorizationCode,
  revokeAppleTokens,
} from "./apple.ts";
import { generateAppleTestKey } from "./test_keys.ts";

const NOW = Date.parse("2026-11-15T10:00:00Z");

async function appleEnv(): Promise<{ env: AppleEnv; publicKey: CryptoKey }> {
  const { pem, publicKey } = await generateAppleTestKey();
  return {
    env: { teamId: "TEAM123456", keyId: "KEY1234567", clientId: "com.exevra.app", privateKey: pem },
    publicKey,
  };
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

Deno.test("client secret is an ES256 JWT with Apple's required claims", async () => {
  const { env, publicKey } = await appleEnv();
  const secret = await createAppleClientSecret(env, NOW);
  assertEquals(decodeProtectedHeader(secret), { alg: "ES256", kid: "KEY1234567" });
  const { payload } = await jwtVerify(secret, publicKey, {
    issuer: "TEAM123456",
    subject: "com.exevra.app",
    audience: "https://appleid.apple.com",
    currentDate: new Date(NOW),
  });
  assertEquals(payload.iat, NOW / 1000);
  assertEquals(payload.exp, NOW / 1000 + 300);
});

Deno.test("exchanges the code and revokes the refresh token", async () => {
  const { env } = await appleEnv();
  using fetchMock = mockFetch((req) =>
    req.url === APPLE_TOKEN_URL
      ? json({ access_token: "a1", refresh_token: "r1", id_token: "x" })
      : new Response(null, { status: 200 })
  );
  const result = await revokeAppleTokens(env, "c1.0.abc", { nowMs: NOW });
  assertEquals(result, { revoked: true });
  assertEquals(fetchMock.calls.map((c) => c.url), [APPLE_TOKEN_URL, APPLE_REVOKE_URL]);

  const exchange = new URLSearchParams(fetchMock.calls[0].body);
  assertEquals(fetchMock.calls[0].headers.get("content-type"), "application/x-www-form-urlencoded");
  assertEquals(exchange.get("client_id"), "com.exevra.app");
  assertEquals(exchange.get("code"), "c1.0.abc");
  assertEquals(exchange.get("grant_type"), "authorization_code");
  assertEquals(exchange.get("client_secret")?.split(".").length, 3);

  const revoke = new URLSearchParams(fetchMock.calls[1].body);
  assertEquals(revoke.get("client_id"), "com.exevra.app");
  assertEquals(revoke.get("token"), "r1");
  assertEquals(revoke.get("token_type_hint"), "refresh_token");
  assertEquals(revoke.get("client_secret"), exchange.get("client_secret"));
});

Deno.test("falls back to revoking the access token when no refresh token is returned", async () => {
  const { env } = await appleEnv();
  using fetchMock = mockFetch((req) =>
    req.url === APPLE_TOKEN_URL ? json({ access_token: "a1" }) : new Response(null)
  );
  assertEquals(await revokeAppleTokens(env, "code", { nowMs: NOW }), { revoked: true });
  const revoke = new URLSearchParams(fetchMock.calls[1].body);
  assertEquals(revoke.get("token"), "a1");
  assertEquals(revoke.get("token_type_hint"), "access_token");
});

Deno.test("reports failures instead of throwing", async () => {
  const { env } = await appleEnv();
  {
    using fetchMock = mockFetch(() => json({ error: "invalid_grant" }, 400));
    assertEquals(await revokeAppleTokens(env, "code", { nowMs: NOW }), {
      revoked: false,
      failure: "token_exchange_failed",
      status: 400,
    });
    assertEquals(fetchMock.calls.length, 1);
  }
  {
    using _fetch = mockFetch(() => Promise.reject(new TypeError("offline")));
    assertEquals(await revokeAppleTokens(env, "code", { nowMs: NOW }), {
      revoked: false,
      failure: "token_exchange_failed",
      status: 0,
    });
  }
  {
    using _fetch = mockFetch(() => json({ token_type: "Bearer" }));
    assertEquals(await revokeAppleTokens(env, "code", { nowMs: NOW }), {
      revoked: false,
      failure: "no_token",
    });
  }
  {
    using _fetch = mockFetch((req) =>
      req.url === APPLE_TOKEN_URL ? json({ refresh_token: "r1" }) : json({}, 503)
    );
    assertEquals(await revokeAppleTokens(env, "code", { nowMs: NOW }), {
      revoked: false,
      failure: "revoke_failed",
      status: 503,
    });
  }
  {
    using fetchMock = mockFetch(() => json({}));
    const bad = {
      ...env,
      privateKey: "-----BEGIN PRIVATE KEY-----\nnope\n-----END PRIVATE KEY-----",
    };
    assertEquals(await revokeAppleTokens(bad, "code", { nowMs: NOW }), {
      revoked: false,
      failure: "client_secret_failed",
    });
    assertEquals(fetchMock.calls.length, 0);
  }
});

Deno.test("isAppleAuthorizationCode accepts Apple's code alphabet only", () => {
  assertEquals(isAppleAuthorizationCode("c0a1b2.0.mrvz.Xy-Z_9"), true);
  assertEquals(isAppleAuthorizationCode(""), false);
  assertEquals(isAppleAuthorizationCode("a b"), false);
  assertEquals(isAppleAuthorizationCode("a&b=c"), false);
  assertEquals(isAppleAuthorizationCode("x".repeat(1025)), false);
  assertEquals(isAppleAuthorizationCode(42), false);
});
