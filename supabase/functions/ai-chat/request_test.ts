import { assertEquals, assertInstanceOf, assertThrows } from "jsr:@std/assert@1.0.19";
import { HttpError } from "../_shared/http.ts";
import { canonicalLocale, isValidTimeZone, parseChatRequest } from "./request.ts";

const base = {
  messages: [{ role: "user", content: "Hi" }],
  tz: "Asia/Kolkata",
};

function code(body: unknown): string {
  const error = assertThrows(() => parseChatRequest(body));
  assertInstanceOf(error, HttpError);
  return error.code;
}

Deno.test("valid request with defaults", () => {
  assertEquals(parseChatRequest(base), {
    messages: [{ role: "user", content: "Hi" }],
    tz: "Asia/Kolkata",
    locale: undefined,
    days: 90,
  });
});

Deno.test("locale is canonicalised and days accepted", () => {
  const parsed = parseChatRequest({ ...base, locale: "en_in", days: 365 });
  assertEquals(parsed.locale, "en-IN");
  assertEquals(parsed.days, 365);
  assertEquals(
    parseChatRequest({ ...base, locale: null, days: null }).days,
    90,
  );
});

Deno.test("extra message fields are ignored", () => {
  const parsed = parseChatRequest({
    ...base,
    messages: [{ role: "user", content: "Hi", id: "x", createdAt: 1 }],
  });
  assertEquals(parsed.messages, [{ role: "user", content: "Hi" }]);
});

Deno.test("invalid requests", () => {
  assertEquals(code(null), "invalid_request");
  assertEquals(code([]), "invalid_request");
  assertEquals(code({ ...base, messages: [null] }), "invalid_request");
  assertEquals(
    code({ ...base, messages: [{ role: "tool", content: "x" }] }),
    "invalid_request",
  );
  assertEquals(code({ ...base, tz: "" }), "invalid_request");
  assertEquals(code({ ...base, tz: "../../etc/passwd" }), "invalid_request");
  assertEquals(code({ ...base, days: "90" }), "invalid_request");
  assertEquals(code({ ...base, locale: 5 }), "invalid_request");
});

Deno.test("length caps are counted in UTF-16 code units", () => {
  // "😀" is two code units, as in Dart's String.length.
  const emoji = "😀".repeat(1000);
  assertEquals(
    parseChatRequest({ ...base, messages: [{ role: "user", content: emoji }] })
      .tz,
    base.tz,
  );
  assertEquals(
    code({ ...base, messages: [{ role: "user", content: `${emoji}x` }] }),
    "too_long",
  );
});

Deno.test("timezone and locale validation", () => {
  for (
    const tz of [
      "UTC",
      "Asia/Kolkata",
      "America/Argentina/Buenos_Aires",
      "Etc/GMT+5",
    ]
  ) {
    assertEquals(isValidTimeZone(tz), true, tz);
  }
  for (const tz of ["Nowhere/City", "Asia Kolkata", "x".repeat(65)]) {
    assertEquals(isValidTimeZone(tz), false, tz);
  }
  assertEquals(canonicalLocale("de-de"), "de-DE");
  assertEquals(canonicalLocale("x"), undefined);
  assertEquals(canonicalLocale("en-US-<script>"), undefined);
});
