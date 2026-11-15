import { assertEquals, assertFalse } from "jsr:@std/assert@1.0.19";
import type { AuthCapableClient, AuthUser, GetUserResult } from "../_shared/auth.ts";
import { envFromRecord, MissingEnvError } from "../_shared/env.ts";
import type { PgErrorLike } from "../_shared/http.ts";
import { createLogger } from "../_shared/log.ts";
import { fakeClock, memorySink, mockFetch } from "../_shared/testing.ts";
import type { AccountAdmin, AuthErrorLike } from "./admin.ts";
import { APPLE_REVOKE_URL, APPLE_TOKEN_URL } from "./apple.ts";
import { createDeleteAccountHandler, type DeleteAccountDeps, hasAppleIdentity } from "./handler.ts";
import { generateAppleTestKey } from "./test_keys.ts";

const JWT = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1MSJ9.c2ln";
const USER_ID = "11111111-1111-4111-8111-111111111111";
const NOW = Date.parse("2026-11-15T10:00:00Z");

const EMAIL_USER: AuthUser = {
  id: USER_ID,
  email: "me@example.com",
  app_metadata: { provider: "email", providers: ["email"] },
};
const APPLE_USER: AuthUser = {
  id: USER_ID,
  email: "relay@privaterelay.appleid.com",
  app_metadata: { provider: "apple", providers: ["apple"] },
};

interface Recorder {
  steps: string[];
  adminsCreated: number;
}

interface Scenario {
  getUser?: GetUserResult | Error;
  prepareError?: PgErrorLike | null;
  deleteError?: AuthErrorLike | null;
  adminThrows?: boolean;
  env?: Record<string, string>;
}

function setup(scenario: Scenario = {}) {
  const rec: Recorder = { steps: [], adminsCreated: 0 };
  const logs = memorySink();
  const clock = fakeClock(NOW);
  const userClient: AuthCapableClient = {
    auth: {
      getUser: () => {
        rec.steps.push("getUser");
        const result = scenario.getUser ?? { data: { user: EMAIL_USER }, error: null };
        return result instanceof Error ? Promise.reject(result) : Promise.resolve(result);
      },
    },
  };
  const admin: AccountAdmin = {
    prepareAccountDeletion: (userId) => {
      rec.steps.push(`prepare:${userId}`);
      return Promise.resolve({ error: scenario.prepareError ?? null });
    },
    deleteUser: (userId) => {
      rec.steps.push(`deleteUser:${userId}`);
      return Promise.resolve({ error: scenario.deleteError ?? null });
    },
  };
  const deps: DeleteAccountDeps = {
    env: envFromRecord(scenario.env ?? {}),
    makeUserClient: () => userClient,
    makeAdmin: () => {
      rec.adminsCreated++;
      if (scenario.adminThrows) throw new MissingEnvError(["SUPABASE_SERVICE_ROLE_KEY"]);
      return admin;
    },
    clock,
    logger: createLogger("delete-account", { sink: logs.sink, clock }),
    requestId: () => "req-1",
  };
  return { handler: createDeleteAccountHandler(deps), rec, logs };
}

function request(body?: unknown, auth: string | null = `Bearer ${JWT}`): Request {
  const headers = new Headers({ "content-type": "application/json" });
  if (auth !== null) headers.set("authorization", auth);
  return new Request("https://project.supabase.co/functions/v1/delete-account", {
    method: "POST",
    headers,
    body: body === undefined ? undefined : typeof body === "string" ? body : JSON.stringify(body),
  });
}

async function appleSecrets(): Promise<Record<string, string>> {
  const { pem } = await generateAppleTestKey();
  return {
    APPLE_TEAM_ID: "TEAM123456",
    APPLE_KEY_ID: "KEY1234567",
    APPLE_CLIENT_ID: "com.exevra.app",
    // Stored with escaped newlines, as `supabase secrets set` usually receives it.
    APPLE_PRIVATE_KEY: pem.replace(/\n/g, "\\n"),
  };
}

function appleUser(): GetUserResult {
  return { data: { user: APPLE_USER }, error: null };
}

Deno.test("no JWT is 401 and touches nothing", async () => {
  const { handler, rec } = setup();
  const res = await handler(request(undefined, null));
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error.code, "unauthorized");
  assertEquals(rec.steps, []);
  assertEquals(rec.adminsCreated, 0);
});

Deno.test("an invalid or expired JWT is 401 and touches nothing", async () => {
  const { handler, rec } = setup({
    getUser: { data: { user: null }, error: { status: 401, name: "AuthApiError" } },
  });
  const res = await handler(request());
  assertEquals(res.status, 401);
  assertEquals(rec.steps, ["getUser"]);
  assertEquals(rec.adminsCreated, 0);
});

Deno.test("success runs prepare_account_deletion, then deleteUser", async () => {
  const { handler, rec, logs } = setup();
  const res = await handler(request());
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { deleted: true, apple_revoked: false });
  assertEquals(rec.steps, ["getUser", `prepare:${USER_ID}`, `deleteUser:${USER_ID}`]);

  const last = logs.lines.at(-1)?.entry;
  assertEquals(last?.status, "deleted");
  assertEquals(last?.apple, "not_linked");
  for (const line of logs.lines) {
    const text = JSON.stringify(line.entry);
    assertFalse(text.includes(USER_ID));
    assertFalse(text.includes("me@example.com"));
    assertFalse(text.includes(JWT));
  }
});

Deno.test("an RPC failure returns 500 deletion_failed and never deletes the user", async () => {
  const { handler, rec, logs } = setup({
    prepareError: { code: "XX000", message: "boom", details: "secret detail" },
  });
  const res = await handler(request());
  assertEquals(res.status, 500);
  const body = await res.json();
  assertEquals(body.error.code, "deletion_failed");
  assertFalse(JSON.stringify(body).includes("boom"));
  assertEquals(rec.steps, ["getUser", `prepare:${USER_ID}`]);
  const entry = logs.lines.at(-1)?.entry;
  assertEquals(entry?.stage, "prepare");
  assertEquals(entry?.code, "XX000");
});

Deno.test("missing service-role config returns 500 deletion_failed", async () => {
  const { handler, rec } = setup({ adminThrows: true });
  const res = await handler(request());
  assertEquals(res.status, 500);
  assertEquals((await res.json()).error.code, "deletion_failed");
  assertEquals(rec.steps, ["getUser"]);
});

Deno.test("an auth outage while verifying the caller returns 500 deletion_failed", async () => {
  const { handler, rec } = setup({ getUser: new TypeError("fetch failed") });
  const res = await handler(request());
  assertEquals(res.status, 500);
  assertEquals((await res.json()).error.code, "deletion_failed");
  assertEquals(rec.adminsCreated, 0);
});

Deno.test("a deleteUser failure returns 500 deletion_failed", async () => {
  const { handler, rec } = setup({ deleteError: { status: 500, name: "AuthApiError" } });
  const res = await handler(request());
  assertEquals(res.status, 500);
  assertEquals((await res.json()).error.code, "deletion_failed");
  assertEquals(rec.steps, ["getUser", `prepare:${USER_ID}`, `deleteUser:${USER_ID}`]);
});

Deno.test("already deleted: a token for a user that no longer exists reports deleted", async () => {
  const gone = {
    status: 403,
    name: "AuthApiError",
    code: "user_not_found",
  } as GetUserResult["error"];
  const { handler, rec, logs } = setup({ getUser: { data: { user: null }, error: gone } });
  const res = await handler(request());
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { deleted: true, apple_revoked: false });
  assertEquals(rec.steps, ["getUser"]);
  assertEquals(rec.adminsCreated, 0);
  assertEquals(logs.lines.at(-1)?.entry.status, "already_deleted");
});

Deno.test("already deleted: deleteUser 404 is treated as success", async () => {
  for (const deleteError of [{ status: 404 }, { status: 400, code: "user_not_found" }]) {
    const { handler, rec } = setup({ deleteError });
    const res = await handler(request());
    assertEquals(res.status, 200);
    assertEquals(await res.json(), { deleted: true, apple_revoked: false });
    assertEquals(rec.steps.at(-1), `deleteUser:${USER_ID}`);
  }
});

Deno.test("Apple users: tokens are revoked between prepare and deleteUser", async () => {
  const env = await appleSecrets();
  const { handler, rec } = setup({ getUser: appleUser(), env });
  using fetchMock = mockFetch((req) => {
    rec.steps.push(req.url === APPLE_TOKEN_URL ? "apple:token" : "apple:revoke");
    return req.url === APPLE_TOKEN_URL
      ? Response.json({ refresh_token: "r1", access_token: "a1" })
      : new Response(null, { status: 200 });
  });
  const res = await handler(request({ apple_authorization_code: "c1.0.abc" }));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { deleted: true, apple_revoked: true });
  assertEquals(rec.steps, [
    "getUser",
    `prepare:${USER_ID}`,
    "apple:token",
    "apple:revoke",
    `deleteUser:${USER_ID}`,
  ]);
  assertEquals(fetchMock.calls.map((c) => c.url), [APPLE_TOKEN_URL, APPLE_REVOKE_URL]);
  assertEquals(new URLSearchParams(fetchMock.calls[1].body).get("token"), "r1");
});

Deno.test("Apple revoke failure is logged but does not block deletion", async () => {
  const env = await appleSecrets();
  const { handler, rec, logs } = setup({ getUser: appleUser(), env });
  using _fetch = mockFetch((req) =>
    req.url === APPLE_TOKEN_URL
      ? Response.json({ refresh_token: "r1" })
      : Response.json({ error: "invalid_client" }, { status: 400 })
  );
  const res = await handler(request({ apple_authorization_code: "c1.0.abc" }));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { deleted: true, apple_revoked: false });
  assertEquals(rec.steps.at(-1), `deleteUser:${USER_ID}`);
  const warn = logs.lines.find((l) => l.level === "warn")?.entry;
  assertEquals(warn?.apple, "revoke_failed");
  assertEquals(warn?.provider_status, 400);
});

Deno.test("Apple token exchange outage does not block deletion", async () => {
  const env = await appleSecrets();
  const { handler, rec } = setup({ getUser: appleUser(), env });
  using _fetch = mockFetch(() => Promise.reject(new TypeError("offline")));
  const res = await handler(request({ apple_authorization_code: "c1.0.abc" }));
  assertEquals(await res.json(), { deleted: true, apple_revoked: false });
  assertEquals(rec.steps.at(-1), `deleteUser:${USER_ID}`);
});

Deno.test("Apple users without a code or without Apple secrets are still deleted", async () => {
  using fetchMock = mockFetch(() => new Response(null));
  const cases: Array<[Record<string, string>, unknown, string]> = [
    [await appleSecrets(), undefined, "no_code"],
    [{}, { apple_authorization_code: "c1" }, "not_configured"],
    [{ APPLE_TEAM_ID: "T" }, { apple_authorization_code: "c1" }, "misconfigured"],
  ];
  for (const [env, body, outcome] of cases) {
    const { handler, rec, logs } = setup({ getUser: appleUser(), env });
    const res = await handler(request(body));
    assertEquals(await res.json(), { deleted: true, apple_revoked: false });
    assertEquals(rec.steps.at(-1), `deleteUser:${USER_ID}`);
    assertEquals(logs.lines.find((l) => l.level === "warn")?.entry.apple, outcome);
  }
  assertEquals(fetchMock.calls.length, 0);
});

Deno.test("a code sent for a non-Apple user is ignored", async () => {
  using fetchMock = mockFetch(() => new Response(null));
  const { handler } = setup({ env: await appleSecrets() });
  const res = await handler(request({ apple_authorization_code: "c1" }));
  assertEquals(await res.json(), { deleted: true, apple_revoked: false });
  assertEquals(fetchMock.calls.length, 0);
});

Deno.test("bodies: empty is fine, malformed is 400 before any deletion step", async () => {
  for (const body of [undefined, "", "  ", "{}", { apple_authorization_code: null }]) {
    const { handler } = setup();
    assertEquals((await handler(request(body))).status, 200, JSON.stringify(body));
  }
  for (
    const body of ["{", "[]", { apple_authorization_code: "a b" }, { apple_authorization_code: 7 }]
  ) {
    const { handler, rec } = setup();
    const res = await handler(request(body));
    assertEquals(res.status, 400, JSON.stringify(body));
    assertEquals(rec.adminsCreated, 0);
  }
  const { handler } = setup();
  assertEquals((await handler(request("x".repeat(9000)))).status, 413);
});

Deno.test("only POST is accepted", async () => {
  const { handler, rec } = setup();
  const res = await handler(new Request("https://x.test/delete-account", { method: "DELETE" }));
  assertEquals(res.status, 405);
  assertEquals(rec.steps, []);
});

Deno.test("hasAppleIdentity checks metadata and identities", () => {
  assertEquals(hasAppleIdentity(APPLE_USER), true);
  assertEquals(hasAppleIdentity(EMAIL_USER), false);
  assertEquals(
    hasAppleIdentity({
      id: "u",
      app_metadata: { provider: "email", providers: ["email", "apple"] },
    }),
    true,
  );
  const withIdentities = { id: "u", identities: [{ provider: "google" }, { provider: "apple" }] };
  assertEquals(hasAppleIdentity(withIdentities as AuthUser), true);
  assertEquals(hasAppleIdentity({ id: "u" }), false);
});
