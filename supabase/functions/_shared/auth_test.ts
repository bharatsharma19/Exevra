import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.19";
import { type AuthCapableClient, authenticate, bearerToken, type GetUserResult } from "./auth.ts";
import { HttpError } from "./http.ts";

const JWT = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln";

function req(authorization?: string): Request {
  const headers = new Headers();
  if (authorization !== undefined) headers.set("authorization", authorization);
  return new Request("http://localhost/fn", { method: "POST", headers });
}

function fakeClient(result: GetUserResult | Error): AuthCapableClient & { seen: string[] } {
  const seen: string[] = [];
  return {
    seen,
    auth: {
      getUser(jwt?: string) {
        seen.push(jwt ?? "");
        return result instanceof Error ? Promise.reject(result) : Promise.resolve(result);
      },
    },
  };
}

Deno.test("bearerToken extracts JWT-shaped bearer tokens only", () => {
  assertEquals(bearerToken(req(`Bearer ${JWT}`)), JWT);
  assertEquals(bearerToken(req(`bearer   ${JWT} `)), JWT);
  assertEquals(bearerToken(new Headers({ authorization: `Bearer ${JWT}` })), JWT);
  assertEquals(bearerToken(req()), null);
  assertEquals(bearerToken(req("Basic abc")), null);
  assertEquals(bearerToken(req("Bearer not-a-jwt")), null);
  assertEquals(bearerToken(req(`Bearer ${JWT} extra`)), null);
  assertEquals(bearerToken(req(`Bearer ${"a".repeat(9000)}.b.c`)), null);
});

Deno.test("authenticate returns the user and a caller-scoped client", async () => {
  const client = fakeClient({ data: { user: { id: "u1", email: "a@b.co" } }, error: null });
  const headers: string[] = [];
  const ctx = await authenticate(req(`Bearer ${JWT}`), (authorization) => {
    headers.push(authorization);
    return client;
  });
  assertEquals(ctx.user.id, "u1");
  assertEquals(ctx.token, JWT);
  assertEquals(ctx.client, client);
  assertEquals(headers, [`Bearer ${JWT}`]);
  assertEquals(client.seen, [JWT]);
});

Deno.test("authenticate rejects missing tokens without creating a client", async () => {
  let created = false;
  const err = await assertRejects(
    () =>
      authenticate(req(), () => {
        created = true;
        return fakeClient({ data: { user: null }, error: null });
      }),
    HttpError,
  );
  assertEquals(err.code, "unauthorized");
  assertEquals(created, false);
});

Deno.test("authenticate maps auth failures", async () => {
  const cases: Array<[GetUserResult | Error, string]> = [
    [{ data: { user: null }, error: { status: 401, name: "AuthApiError" } }, "unauthorized"],
    [{ data: { user: null }, error: { status: 403, name: "AuthApiError" } }, "unauthorized"],
    [{ data: { user: null }, error: null }, "unauthorized"],
    [{ data: { user: { id: "" } }, error: null }, "unauthorized"],
    [{ data: { user: null }, error: { status: 503, name: "AuthApiError" } }, "unavailable"],
    [{ data: { user: null }, error: { name: "AuthRetryableFetchError" } }, "unavailable"],
    [new TypeError("fetch failed"), "unavailable"],
  ];
  for (const [result, code] of cases) {
    const err = await assertRejects(
      () => authenticate(req(`Bearer ${JWT}`), () => fakeClient(result)),
      HttpError,
    );
    assertEquals(err.code, code);
  }
});
