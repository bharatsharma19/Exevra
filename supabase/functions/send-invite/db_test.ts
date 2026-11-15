import { assertEquals } from "jsr:@std/assert@1.0.19";
import { createUserClient } from "../_shared/auth.ts";
import { mockFetch } from "../_shared/testing.ts";
import { parseCreatedInvitation, supabaseInviteDb } from "./db.ts";

const ENV = { url: "https://project.supabase.test", anonKey: "anon-test-key" };
const AUTH = "Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1MSJ9.c2ln";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

Deno.test("parseCreatedInvitation accepts a table row or object and rejects junk", () => {
  const row = {
    invitation_id: "i1",
    token: "t1",
    expires_at: "2026-11-22T00:00:00Z",
  };
  const expected = {
    invitationId: "i1",
    token: "t1",
    expiresAt: "2026-11-22T00:00:00Z",
  };
  assertEquals(parseCreatedInvitation([row]), expected);
  assertEquals(parseCreatedInvitation(row), expected);
  assertEquals(
    parseCreatedInvitation([{ ...row, expires_at: null }])?.expiresAt,
    null,
  );
  assertEquals(parseCreatedInvitation([]), null);
  assertEquals(parseCreatedInvitation(null), null);
  assertEquals(parseCreatedInvitation([{ ...row, token: 1 }]), null);
});

Deno.test("createInvitation calls the RPC as the caller", async () => {
  using fetchMock = mockFetch(() =>
    json([{
      invitation_id: "i1",
      token: "t1",
      expires_at: "2026-11-22T00:00:00Z",
    }])
  );
  const db = supabaseInviteDb(createUserClient(ENV, AUTH));
  const result = await db.createInvitation("g1", "a@b.co", "viewer");
  assertEquals(result.error, null);
  assertEquals(result.data?.token, "t1");

  const call = fetchMock.calls[0];
  assertEquals(call.method, "POST");
  assertEquals(
    call.url,
    "https://project.supabase.test/rest/v1/rpc/create_group_invitation",
  );
  assertEquals(call.headers.get("authorization"), AUTH);
  assertEquals(call.headers.get("apikey"), "anon-test-key");
  assertEquals(JSON.parse(call.body), {
    p_group_id: "g1",
    p_email: "a@b.co",
    p_role: "viewer",
  });
});

Deno.test("createInvitation surfaces Postgres errors with their SQLSTATE", async () => {
  using _fetch = mockFetch(() =>
    json(
      { code: "P0001", message: "rate_limited", details: null, hint: null },
      400,
    )
  );
  const db = supabaseInviteDb(createUserClient(ENV, AUTH));
  const result = await db.createInvitation("g1", "a@b.co", "member");
  assertEquals(result.data, null);
  assertEquals(result.error?.code, "P0001");
  assertEquals(result.error?.message, "rate_limited");
});

Deno.test("name lookups read single rows and never throw", async () => {
  {
    using fetchMock = mockFetch((req) =>
      json(
        req.url.includes("/groups?") ? { name: "Flat" } : { display_name: "Asha" },
      )
    );
    const db = supabaseInviteDb(createUserClient(ENV, AUTH));
    assertEquals(await db.getGroupName("g1"), "Flat");
    assertEquals(await db.getDisplayName("u1"), "Asha");
    assertEquals(
      fetchMock.calls[0].url,
      "https://project.supabase.test/rest/v1/groups?select=name&id=eq.g1",
    );
  }
  {
    using _fetch = mockFetch(() => Promise.reject(new TypeError("offline")));
    const db = supabaseInviteDb(createUserClient(ENV, AUTH));
    assertEquals(await db.getGroupName("g1"), null);
    assertEquals(await db.getDisplayName("u1"), null);
  }
});
