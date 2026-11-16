import { assertEquals } from "jsr:@std/assert@1.0.19";
import { escapeHtml, html, SafeHtml, safeHttpsUrl, toSingleLine, trustedHtml } from "./html.ts";

Deno.test("escapeHtml escapes markup and attribute breakers", () => {
  assertEquals(
    escapeHtml(`<script>alert("x")</script> & 'y' \`z\` a=b`),
    "&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt; &amp; &#39;y&#39; &#96;z&#96; a&#61;b",
  );
  assertEquals(escapeHtml(null), "");
  assertEquals(escapeHtml(undefined), "");
  assertEquals(escapeHtml(42), "42");
});

Deno.test("html escapes interpolations but keeps SafeHtml", () => {
  const name = `<img src=x onerror="alert(1)">`;
  const bold = html`<b>${name}</b>`;
  assertEquals(bold instanceof SafeHtml, true);
  assertEquals(
    bold.toString(),
    "<b>&lt;img src&#61;x onerror&#61;&quot;alert(1)&quot;&gt;</b>",
  );
  const page = html`<p>${bold}${trustedHtml("<br>")}${["<a>", html`<i>ok</i>`]}</p>`;
  assertEquals(
    page.value,
    "<p><b>&lt;img src&#61;x onerror&#61;&quot;alert(1)&quot;&gt;</b><br>&lt;a&gt;<i>ok</i></p>",
  );
});

Deno.test("toSingleLine strips line breaks and truncates by code point", () => {
  assertEquals(
    toSingleLine("Trip\r\nBcc: evil@example.com\t ok", 100),
    "Trip Bcc: evil@example.com ok",
  );
  assertEquals(toSingleLine("  abcdef  ", 4), "abc…");
  assertEquals(toSingleLine("😀😀😀😀😀", 3), "😀😀…");
  assertEquals(toSingleLine("short", 10), "short");
  // Format and bidi controls (RLO, zero-width, BOM, isolates) are removed, not replaced.
  assertEquals(toSingleLine("a\u202Ebc\u202C d\u200Be\uFEFF\u2067f\u2069", 20), "abc def");
});

Deno.test("safeHttpsUrl accepts only plain https URLs", () => {
  assertEquals(safeHttpsUrl("https://exevra.app/invite?t=a"), "https://exevra.app/invite?t=a");
  assertEquals(safeHttpsUrl("http://exevra.app"), null);
  assertEquals(safeHttpsUrl("javascript:alert(1)"), null);
  assertEquals(safeHttpsUrl("https://u:p@exevra.app"), null);
  assertEquals(safeHttpsUrl("nope"), null);
});
