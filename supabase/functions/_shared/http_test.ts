import {
  assertEquals,
  assertInstanceOf,
  assertRejects,
  assertThrows,
} from "jsr:@std/assert@1.0.19";
import {
  assertMethod,
  DEFAULT_ERROR_MESSAGES,
  ERROR_CODES,
  ERROR_STATUS,
  errorResponse,
  errorResponseFrom,
  HttpError,
  httpErrorFromPg,
  isErrorCode,
  jsonResponse,
  pgErrorKey,
  readJsonBody,
} from "./http.ts";

function post(body: BodyInit | null, headers: HeadersInit = {}): Request {
  return new Request("http://localhost/fn", { method: "POST", body, headers });
}

Deno.test("every error code has a status and a friendly message", () => {
  for (const code of ERROR_CODES) {
    assertEquals(typeof ERROR_STATUS[code], "number");
    assertEquals(DEFAULT_ERROR_MESSAGES[code].length > 10, true);
  }
  assertEquals(ERROR_STATUS.consent_required, 403);
  assertEquals(ERROR_STATUS.too_long, 413);
  assertEquals(ERROR_STATUS.quota_exceeded, 429);
  assertEquals(ERROR_STATUS.unavailable, 503);
  assertEquals(isErrorCode("rate_limited"), true);
  assertEquals(isErrorCode("nope"), false);
});

Deno.test("jsonResponse sets JSON and no-store headers", async () => {
  const res = jsonResponse({ ok: true }, { status: 201, headers: { "x-extra": "1" } });
  assertEquals(res.status, 201);
  assertEquals(res.headers.get("content-type"), "application/json; charset=utf-8");
  assertEquals(res.headers.get("cache-control"), "no-store");
  assertEquals(res.headers.get("x-extra"), "1");
  assertEquals(await res.json(), { ok: true });
});

Deno.test("errorResponse uses the error body shape", async () => {
  const res = errorResponse("too_long");
  assertEquals(res.status, 413);
  assertEquals(await res.json(), {
    error: { code: "too_long", message: DEFAULT_ERROR_MESSAGES.too_long },
  });
  const custom = errorResponse("conflict", "Already a member.", { reason: "already_member" });
  assertEquals(await custom.json(), {
    error: { code: "conflict", message: "Already a member.", reason: "already_member" },
  });
});

Deno.test("errorResponseFrom hides unknown errors", async () => {
  const res = errorResponseFrom(new Error("db password is hunter2"));
  assertEquals(res.status, 500);
  const body = await res.json();
  assertEquals(body.error.code, "internal");
  assertEquals(JSON.stringify(body).includes("hunter2"), false);
  assertEquals(errorResponseFrom(new HttpError("unauthorized")).status, 401);
});

Deno.test("assertMethod rejects other methods with an allow header", () => {
  assertMethod(post("{}"), "POST");
  const err = assertThrows(
    () => assertMethod(new Request("http://localhost/fn"), "POST"),
    HttpError,
  );
  assertEquals(err.code, "method_not_allowed");
  assertEquals(new Headers(err.headers).get("allow"), "POST");
});

Deno.test("readJsonBody parses JSON", async () => {
  assertEquals(await readJsonBody(post('{"a":1}', { "content-type": "application/json" })), {
    a: 1,
  });
  assertEquals(await readJsonBody(post("[1]")), [1]);
});

Deno.test("readJsonBody rejects bad input with typed codes", async () => {
  const cases: Array<[Request, string]> = [
    [post("{", { "content-type": "application/json" }), "invalid_request"],
    [post("   "), "invalid_request"],
    [post(null), "invalid_request"],
    [post("a=1", { "content-type": "application/x-www-form-urlencoded" }), "invalid_request"],
    [post(new Uint8Array([0xff, 0xfe])), "invalid_request"],
  ];
  for (const [req, code] of cases) {
    const err = await assertRejects(() => readJsonBody(req), HttpError);
    assertEquals(err.code, code);
  }
});

Deno.test("readJsonBody enforces the size cap while streaming", async () => {
  const big = JSON.stringify({ text: "x".repeat(200) });
  const err = await assertRejects(() => readJsonBody(post(big), { maxBytes: 100 }), HttpError);
  assertEquals(err.code, "too_long");

  const declared = post("{}", { "content-length": "999999" });
  const err2 = await assertRejects(() => readJsonBody(declared, { maxBytes: 100 }), HttpError);
  assertEquals(err2.code, "too_long");

  const chunks = new ReadableStream<Uint8Array>({
    start(controller) {
      for (let i = 0; i < 10; i++) controller.enqueue(new TextEncoder().encode('"xxxxxxxxxx'));
      controller.close();
    },
  });
  const err3 = await assertRejects(() => readJsonBody(post(chunks), { maxBytes: 50 }), HttpError);
  assertEquals(err3.code, "too_long");
});

Deno.test("pgErrorKey only reads P0001 business keys", () => {
  assertEquals(pgErrorKey({ code: "P0001", message: "quota_exceeded" }), "quota_exceeded");
  assertEquals(pgErrorKey({ code: "P0001", message: "  invite_expired " }), "invite_expired");
  assertEquals(pgErrorKey({ code: "P0001", message: "Some sentence with spaces" }), undefined);
  assertEquals(pgErrorKey({ code: "42501", message: "quota_exceeded" }), undefined);
  assertEquals(pgErrorKey(null), undefined);
});

Deno.test("httpErrorFromPg maps business keys and SQLSTATEs", () => {
  const quota = httpErrorFromPg({ code: "P0001", message: "quota_exceeded" });
  assertInstanceOf(quota, HttpError);
  assertEquals([quota.code, quota.status, quota.reason], ["quota_exceeded", 429, "quota_exceeded"]);
  assertEquals(httpErrorFromPg({ code: "P0001", message: "rate_limited" }).code, "rate_limited");

  const expired = httpErrorFromPg({ code: "P0001", message: "invite_expired" });
  assertEquals([expired.code, expired.reason], ["conflict", "invite_expired"]);
  const mapped = httpErrorFromPg(
    { code: "P0001", message: "invite_expired" },
    { invite_expired: "not_found" },
  );
  assertEquals(mapped.code, "not_found");

  assertEquals(httpErrorFromPg({ code: "42501", message: "x" }).code, "forbidden");
  assertEquals(httpErrorFromPg({ code: "P0002", message: "x" }).code, "not_found");
  assertEquals(httpErrorFromPg({ code: "22023", message: "x" }).code, "invalid_request");
  assertEquals(httpErrorFromPg({ code: "23505", message: "x" }).code, "conflict");
  assertEquals(httpErrorFromPg({ code: "PGRST301", message: "x" }).code, "unauthorized");
  const unknown = httpErrorFromPg({ code: "XX000", message: "secret detail" });
  assertEquals(unknown.code, "internal");
  assertEquals(unknown.message.includes("secret"), false);
});
