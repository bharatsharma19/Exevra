import { assert, assertEquals, assertFalse, assertStringIncludes } from "jsr:@std/assert@1.0.19";
import type { GetUserResult } from "../_shared/auth.ts";
import { envFromRecord } from "../_shared/env.ts";
import type { PgErrorLike } from "../_shared/http.ts";
import { createLogger } from "../_shared/log.ts";
import { fakeClock, memorySink, mockFetch } from "../_shared/testing.ts";
import type { CreateInvitationResult, InviteDb, InviteRole } from "./db.ts";
import { createSendInviteHandler, type SendInviteDeps } from "./handler.ts";
import { RESEND_EMAILS_URL } from "./resend.ts";

const JWT = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1MSJ9.c2ln";
const USER_ID = "11111111-1111-4111-8111-111111111111";
const GROUP_ID = "22222222-2222-4222-8222-222222222222";
const INVITATION_ID = "33333333-3333-4333-8333-333333333333";
const TOKEN = "AbC_dEf-0123456789abcdefghijklmnopqrstuvwxy";
const NOW = Date.parse("2026-11-15T10:00:00Z");
const EXPIRES = "2026-11-22T10:00:00Z";

const FULL_ENV = {
  APP_BASE_URL: "https://exevra.app",
  RESEND_API_KEY: "test-resend-key",
  INVITE_FROM_EMAIL: "Exevra <invites@exevra.app>",
};

interface FakeDbOptions {
  user?: GetUserResult;
  create?: CreateInvitationResult;
  groupName?: string | null;
  displayName?: string | null;
}

interface FakeDb extends InviteDb {
  creates: Array<{ groupId: string; email: string; role: InviteRole }>;
  authorizations: string[];
}

function fakeDb(options: FakeDbOptions = {}): FakeDb {
  const creates: FakeDb["creates"] = [];
  return {
    creates,
    authorizations: [],
    auth: {
      getUser: () =>
        Promise.resolve(
          options.user ?? { data: { user: { id: USER_ID } }, error: null },
        ),
    },
    createInvitation(groupId, email, role) {
      creates.push({ groupId, email, role });
      return Promise.resolve(
        options.create ?? {
          data: {
            invitationId: INVITATION_ID,
            token: TOKEN,
            expiresAt: EXPIRES,
          },
          error: null,
        },
      );
    },
    getGroupName: () =>
      Promise.resolve(
        options.groupName === undefined ? "Flatmates" : options.groupName,
      ),
    getDisplayName: () =>
      Promise.resolve(
        options.displayName === undefined ? "Asha" : options.displayName,
      ),
  };
}

function setup(
  db: FakeDb,
  env: Record<string, string> = FULL_ENV,
  extra: Partial<SendInviteDeps> = {},
) {
  const logs = memorySink();
  const clock = fakeClock(NOW);
  const handler = createSendInviteHandler({
    env: envFromRecord(env),
    makeClient: (authorization) => {
      db.authorizations.push(authorization);
      return db;
    },
    clock,
    logger: createLogger("send-invite", { sink: logs.sink, clock }),
    requestId: () => "req-1",
    ...extra,
  });
  return { handler, logs };
}

function request(
  body: unknown,
  init: { auth?: string | null; headers?: Record<string, string> } = {},
): Request {
  const headers = new Headers({
    "content-type": "application/json",
    ...init.headers,
  });
  if (init.auth !== null) {
    headers.set("authorization", init.auth ?? `Bearer ${JWT}`);
  }
  return new Request("https://project.supabase.co/functions/v1/send-invite", {
    method: "POST",
    headers,
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

const VALID = {
  group_id: GROUP_ID,
  email: "  Friend@Example.COM ",
  role: "viewer",
};

function resendOk(): Response {
  return new Response(JSON.stringify({ id: "email-1" }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

Deno.test("success sends through Resend with the idempotency key and reports sent:true", async () => {
  using fetchMock = mockFetch(() => resendOk());
  const db = fakeDb();
  const { handler, logs } = setup(db);

  const res = await handler(request(VALID));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), {
    invitation_id: INVITATION_ID,
    sent: true,
    expires_at: EXPIRES,
  });

  assertEquals(db.creates, [{
    groupId: GROUP_ID,
    email: "friend@example.com",
    role: "viewer",
  }]);
  assertEquals(db.authorizations, [`Bearer ${JWT}`]);

  assertEquals(fetchMock.calls.length, 1);
  const call = fetchMock.calls[0];
  assertEquals(call.url, RESEND_EMAILS_URL);
  assertEquals(call.method, "POST");
  assertEquals(call.headers.get("authorization"), "Bearer test-resend-key");
  assertEquals(call.headers.get("idempotency-key"), INVITATION_ID);
  const sent = JSON.parse(call.body);
  assertEquals(sent.from, "Exevra <invites@exevra.app>");
  assertEquals(sent.to, ["friend@example.com"]);
  assertEquals(sent.subject, "Asha invited you to Flatmates on Exevra");
  assertStringIncludes(sent.html, `href="https://exevra.app/invite/${TOKEN}"`);
  assertStringIncludes(sent.text, `https://exevra.app/invite/${TOKEN}`);
  assertStringIncludes(sent.text, "expires in 7 days");

  // One log line, with no email address, user id, token or names.
  assertEquals(logs.lines.length, 1);
  const line = JSON.stringify(logs.lines[0].entry);
  assertEquals(logs.lines[0].entry.status, "sent");
  for (
    const secret of [
      "friend@example.com",
      USER_ID,
      TOKEN,
      "Asha",
      "Flatmates",
      JWT,
    ]
  ) {
    assertFalse(line.includes(secret), `log leaked ${secret}`);
  }
});

Deno.test("names with markup, quotes and ampersands are escaped in the HTML", async () => {
  using fetchMock = mockFetch(() => resendOk());
  const db = fakeDb({
    displayName: `<script>alert("x")</script>`,
    groupName: `Tom & Jerry's "flat" <b>`,
  });
  const { handler } = setup(db);
  const res = await handler(request(VALID));
  assertEquals((await res.json()).sent, true);

  const sent = JSON.parse(fetchMock.calls[0].body);
  assertFalse(sent.html.includes("<script>"));
  assertFalse(sent.html.includes("<b>"));
  assertStringIncludes(
    sent.html,
    "&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;",
  );
  assertStringIncludes(
    sent.html,
    "Tom &amp; Jerry&#39;s &quot;flat&quot; &lt;b&gt;",
  );
  // The subject is plain text (a JSON string, not HTML) but stays on one line.
  assertEquals(
    sent.subject,
    `<script>alert("x")</script> invited you to Tom & Jerry's "flat" <b> on Exevra`,
  );
});

Deno.test("the link base comes from APP_BASE_URL, never from the request", async () => {
  using _fetch = mockFetch(() => new Response("nope", { status: 500 }));
  const db = fakeDb();
  const { handler } = setup(db, {
    ...FULL_ENV,
    APP_BASE_URL: "https://links.exevra.app/",
  });
  const res = await handler(
    request(
      {
        ...VALID,
        app_base_url: "https://evil.example",
        link: "https://evil.example",
      },
      {
        headers: {
          origin: "https://evil.example",
          host: "evil.example",
          "x-forwarded-host": "evil.example",
          referer: "https://evil.example/",
        },
      },
    ),
  );
  const body = await res.json();
  assertEquals(body.share_url, `https://links.exevra.app/invite/${TOKEN}`);
});

Deno.test("missing APP_BASE_URL is 503 and creates no invitation", async () => {
  using fetchMock = mockFetch(() => resendOk());
  const db = fakeDb();
  const { handler } = setup(db, {
    RESEND_API_KEY: "k",
    INVITE_FROM_EMAIL: "a@b.co",
  });
  const res = await handler(request(VALID));
  assertEquals(res.status, 503);
  assertEquals((await res.json()).error.code, "unavailable");
  assertEquals(db.creates.length, 0);
  assertEquals(fetchMock.calls.length, 0);
});

Deno.test("missing Resend key returns sent:false with a share_url and calls no provider", async () => {
  using fetchMock = mockFetch(() => resendOk());
  const db = fakeDb();
  const { handler } = setup(db, { APP_BASE_URL: "https://exevra.app" });
  const res = await handler(request(VALID));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), {
    invitation_id: INVITATION_ID,
    sent: false,
    expires_at: EXPIRES,
    reason: "email_not_configured",
    share_url: `https://exevra.app/invite/${TOKEN}`,
  });
  assertEquals(fetchMock.calls.length, 0);
});

Deno.test("Resend non-2xx returns sent:false with reason email_failed", async () => {
  for (const status of [400, 403, 409, 422, 429, 500, 503]) {
    using _fetch = mockFetch(() => new Response(JSON.stringify({ message: "bad" }), { status }));
    const { handler, logs } = setup(fakeDb());
    const res = await handler(request(VALID));
    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(body.sent, false, `status ${status}`);
    assertEquals(body.reason, "email_failed");
    assertEquals(body.share_url, `https://exevra.app/invite/${TOKEN}`);
    assertEquals(logs.lines[0].level, "warn");
    assertEquals(logs.lines[0].entry.provider_status, status);
  }
});

Deno.test("a network failure talking to Resend returns sent:false", async () => {
  using _fetch = mockFetch(() => Promise.reject(new TypeError("connection refused")));
  const { handler } = setup(fakeDb());
  const body = await (await handler(request(VALID))).json();
  assertEquals(body.sent, false);
  assertEquals(body.reason, "email_failed");
});

Deno.test("the RPC's rate limit maps to 429 rate_limited", async () => {
  using fetchMock = mockFetch(() => resendOk());
  const db = fakeDb({
    create: { data: null, error: { code: "P0001", message: "rate_limited" } },
  });
  const { handler } = setup(db);
  const res = await handler(request(VALID));
  assertEquals(res.status, 429);
  const body = await res.json();
  assertEquals(body.error.code, "rate_limited");
  assertEquals(body.error.reason, "rate_limited");
  assertEquals(fetchMock.calls.length, 0);
});

Deno.test("RPC errors map to friendly HTTP errors", async () => {
  const cases: Array<[PgErrorLike, number, string, string | undefined]> = [
    [
      { code: "42501", message: "not_group_admin" },
      403,
      "forbidden",
      "not_group_admin",
    ],
    [
      { code: "42501", message: "permission denied for function" },
      403,
      "forbidden",
      undefined,
    ],
    [
      { code: "P0002", message: "group_not_found" },
      404,
      "not_found",
      "group_not_found",
    ],
    [
      { code: "23505", message: "already_member" },
      409,
      "conflict",
      "already_member",
    ],
    [
      { code: "23505", message: "duplicate key value" },
      409,
      "conflict",
      undefined,
    ],
    [
      { code: "22023", message: "invalid_email" },
      400,
      "invalid_request",
      "invalid_email",
    ],
    [
      { code: "PGRST301", message: "JWT expired" },
      401,
      "unauthorized",
      undefined,
    ],
    [{ code: "XX000", message: "boom" }, 500, "internal", undefined],
    [
      { code: "fetch_failed", message: "fetch_failed" },
      500,
      "internal",
      undefined,
    ],
  ];
  for (const [error, status, code, reason] of cases) {
    using fetchMock = mockFetch(() => resendOk());
    const { handler } = setup(fakeDb({ create: { data: null, error } }));
    const res = await handler(request(VALID));
    assertEquals(res.status, status, error.message ?? "");
    const body = await res.json();
    assertEquals(body.error.code, code);
    assertEquals(body.error.reason, reason);
    assertFalse(JSON.stringify(body).includes("duplicate key"));
    assertEquals(fetchMock.calls.length, 0);
  }
});

Deno.test("requests without a valid JWT are rejected before any database call", async () => {
  const db = fakeDb();
  const { handler } = setup(db);
  const res = await handler(request(VALID, { auth: null }));
  assertEquals(res.status, 401);
  assertEquals(db.authorizations.length, 0);

  const expired = fakeDb({
    user: { data: { user: null }, error: { status: 401 } },
  });
  const res2 = await setup(expired).handler(request(VALID));
  assertEquals(res2.status, 401);
  assertEquals(expired.creates.length, 0);
});

Deno.test("input validation rejects bad emails, roles and group ids", async () => {
  const bad: unknown[] = [
    { ...VALID, email: "not-an-email" },
    { ...VALID, email: "a@b" },
    { ...VALID, email: `${"a".repeat(250)}@example.com` },
    { ...VALID, email: "a@b.co\r\nBcc: x@y.co" },
    { ...VALID, email: 42 },
    { ...VALID, role: "admin" },
    { ...VALID, group_id: "not-a-uuid" },
    { email: "a@b.co" },
    [VALID],
    "not json",
  ];
  for (const body of bad) {
    const db = fakeDb();
    const res = await setup(db).handler(request(body));
    assertEquals(res.status, 400, JSON.stringify(body));
    assertEquals((await res.json()).error.code, "invalid_request");
    assertEquals(db.creates.length, 0);
  }
});

Deno.test("role defaults to member and other methods are rejected", async () => {
  using _fetch = mockFetch(() => resendOk());
  const db = fakeDb();
  const { handler } = setup(db);
  const res = await handler(request({ group_id: GROUP_ID, email: "x@y.co" }));
  assertEquals(res.status, 200);
  assertEquals(db.creates[0].role, "member");

  const get = await handler(
    new Request("https://x.test/send-invite", { method: "GET" }),
  );
  assertEquals(get.status, 405);
  assertEquals(get.headers.get("allow"), "POST");
});

Deno.test("an unexpected token shape is never put into a link", async () => {
  using fetchMock = mockFetch(() => resendOk());
  const db = fakeDb({
    create: {
      data: {
        invitationId: INVITATION_ID,
        token: "../../evil?x=1",
        expiresAt: EXPIRES,
      },
      error: null,
    },
  });
  const res = await setup(db).handler(request(VALID));
  assertEquals(res.status, 500);
  assertEquals(fetchMock.calls.length, 0);
});

Deno.test("missing names fall back to neutral copy", async () => {
  using fetchMock = mockFetch(() => resendOk());
  const db = fakeDb({ groupName: null, displayName: "   " });
  const res = await setup(db).handler(request(VALID));
  assert((await res.json()).sent);
  const sent = JSON.parse(fetchMock.calls[0].body);
  assertEquals(sent.subject, "Someone invited you to a group on Exevra");
});
