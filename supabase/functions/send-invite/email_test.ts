import { assertEquals, assertFalse, assertStringIncludes } from "jsr:@std/assert@1.0.19";
import { FALLBACK_GROUP, FALLBACK_INVITER, looksLikeUrl, renderInviteEmail } from "./email.ts";

const BASE = {
  inviterName: "Asha",
  groupName: "Flatmates",
  role: "member" as const,
  recipientEmail: "friend@example.com",
  link: "https://exevra.app/invite/tok_123",
  expiresInDays: 7,
};

Deno.test("renders subject, HTML and text with the invite link", () => {
  const email = renderInviteEmail(BASE);
  assertEquals(email.subject, "Asha invited you to Flatmates on Exevra");
  assertStringIncludes(
    email.html,
    `<a href="https://exevra.app/invite/tok_123"`,
  );
  assertStringIncludes(email.html, "<strong>Asha</strong>");
  assertStringIncludes(email.html, "friend@example.com");
  assertStringIncludes(email.text, "https://exevra.app/invite/tok_123");
  assertStringIncludes(email.text, "As a member you can add shared expenses");
  assertStringIncludes(email.text, "expires in 7 days");
  assertStringIncludes(
    renderInviteEmail({ ...BASE, role: "viewer" }).text,
    "As a viewer",
  );
  assertStringIncludes(
    renderInviteEmail({ ...BASE, expiresInDays: 1 }).text,
    "in 1 day.",
  );
});

Deno.test("every interpolated value is HTML-escaped", () => {
  const email = renderInviteEmail({
    ...BASE,
    inviterName: `<script>alert('x')</script>`,
    groupName: `A & B "quoted" <img src=x onerror=alert(1)>`,
    recipientEmail: "o'brien@example.com",
    link: `https://exevra.app/invite/a"onmouseover="alert(1)`,
  });
  assertFalse(email.html.includes("<script>"));
  assertFalse(email.html.includes("<img"));
  assertFalse(email.html.includes(`"onmouseover`));
  assertStringIncludes(
    email.html,
    "&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;",
  );
  assertStringIncludes(
    email.html,
    "A &amp; B &quot;quoted&quot; &lt;img src&#61;x onerror&#61;alert(1)&gt;",
  );
  assertStringIncludes(email.html, "o&#39;brien@example.com");
  assertStringIncludes(email.html, "a&quot;onmouseover&#61;&quot;alert(1)");
});

Deno.test("names are flattened to one line and truncated", () => {
  const email = renderInviteEmail({
    ...BASE,
    inviterName: "Evil\r\nBcc: victim",
    groupName: "G".repeat(200),
  });
  assertFalse(email.subject.includes("\n"));
  assertFalse(email.subject.includes("\r"));
  assertStringIncludes(email.subject, "Evil Bcc: victim invited you to ");
  assertStringIncludes(email.subject, `${"G".repeat(59)}…`);
  assertFalse(email.subject.includes("G".repeat(61)));
});

Deno.test("bidi and zero-width characters are removed from names", () => {
  const email = renderInviteEmail({
    ...BASE,
    inviterName: "Support \u202Emaet\u202C \u200Bteam\u2066\uFEFF",
    groupName: "Fl\u200Dat\u00ADmates\u{E0041}",
  });
  for (const value of [email.subject, email.html, email.text]) {
    assertFalse(/[\u200B-\u200F\u202A-\u202E\u2060-\u2069\uFEFF\u00AD]/u.test(value), value);
    assertFalse(/\p{Cf}/u.test(value));
  }
  assertEquals(email.subject, "Support maet team invited you to Flatmates on Exevra");
  // Reversed domains are caught once the override is gone.
  assertEquals(
    renderInviteEmail({ ...BASE, inviterName: "\u202Emoc.lapyap" }).subject,
    `${FALLBACK_INVITER} invited you to Flatmates on Exevra`,
  );
});

Deno.test("URL-, domain- and email-shaped names fall back to neutral copy", () => {
  for (
    const name of [
      "Account locked: verify at evil.example/x",
      "https://evil.example",
      "Visit www.evil",
      "paypal.com support",
      "pay\u200Bpal.com",
      "evil\uFF0Eexample", // fullwidth full stop
      "help@evil.example",
    ]
  ) {
    assertEquals(looksLikeUrl(name), true, name);
    const email = renderInviteEmail({ ...BASE, inviterName: name, groupName: name });
    assertEquals(email.subject, `${FALLBACK_INVITER} invited you to ${FALLBACK_GROUP} on Exevra`);
    assertFalse(email.html.includes("evil"), name);
    assertFalse(email.text.includes("evil"), name);
  }
  for (const name of ["Asha", "Trip 2.0", "Goa trip, Dec. 2026", "J. Doe", "Flat #4"]) {
    assertEquals(looksLikeUrl(name), false, name);
  }
});
