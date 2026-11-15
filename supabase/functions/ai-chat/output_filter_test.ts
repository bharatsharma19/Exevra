import { assertEquals, assertFalse } from "jsr:@std/assert@1.0.19";
import { createOutputFilter, MAX_HOLD_CHARS, stripImages } from "./output_filter.ts";

/** Feeds `chunks` through one filter and returns every emitted piece plus the flush. */
function run(chunks: readonly string[]): { pieces: string[]; text: string } {
  const filter = createOutputFilter();
  const pieces = chunks.map((chunk) => filter.push(chunk));
  pieces.push(filter.flush());
  return { pieces, text: pieces.join("") };
}

Deno.test("inline and reference images become their alt text", () => {
  assertEquals(
    stripImages("Here: ![x](https://evil.example/c?d=food_12345) done"),
    "Here: x done",
  );
  assertEquals(stripImages("A ![chart][1] B"), "A chart B");
  assertEquals(stripImages('![a](<https://e/x y> "t")'), "a");
  assertEquals(stripImages("![nested ![in](https://e/1)](https://e/2)"), "nested in");
  assertEquals(stripImages("![](https://e/p?d=1)"), "");
});

Deno.test("shortcut reference images lose the '!' and links are left alone", () => {
  assertEquals(stripImages("See ![logo] now"), "See [logo] now");
  assertEquals(stripImages("[Verify](https://evil.example)"), "[Verify](https://evil.example)");
  assertEquals(stripImages("Wow! [a](b) and !important"), "Wow! [a](b) and !important");
});

Deno.test("HTML img tags are removed; other angle brackets are kept", () => {
  assertEquals(stripImages('x <img src="https://e/p?d=1"> y'), "x  y");
  assertEquals(stripImages("x <IMG/src=https://e> y"), "x  y");
  assertEquals(stripImages("1 < 2 and <b>bold</b> <image>"), "1 < 2 and <b>bold</b> <image>");
});

Deno.test("an image split across chunks never leaks, at any split point", () => {
  const source = "Total ₹1,200. ![x](https://evil.example/c?d=food_12345) Bye <img src=e>!";
  for (let cut = 0; cut <= source.length; cut++) {
    for (let cut2 = cut; cut2 <= source.length; cut2 += 7) {
      const { pieces, text } = run([
        source.slice(0, cut),
        source.slice(cut, cut2),
        source.slice(cut2),
      ]);
      assertEquals(text, "Total ₹1,200. x Bye !");
      for (const piece of pieces) {
        assertFalse(piece.includes("evil.example"), `leaked at ${cut}/${cut2}`);
      }
    }
  }
});

Deno.test("text without image syntax is passed through immediately", () => {
  const filter = createOutputFilter();
  assertEquals(filter.push("You spent **₹12,345** "), "You spent **₹12,345** ");
  assertEquals(filter.push("on food!"), "on food");
  assertEquals(filter.push(" Nice."), "! Nice.");
  assertEquals(filter.flush(), "");
});

Deno.test("an unfinished image is neutralised at the end or past the hold limit", () => {
  assertEquals(run(["Look ![x](https://evil.example/"]).text, "Look [x](https://evil.example/");
  assertEquals(run(["a <img src=x"]).text, "a img src=x");

  const filter = createOutputFilter();
  assertEquals(filter.push("![x]("), "");
  const long = "a".repeat(MAX_HOLD_CHARS);
  const out = filter.push(long);
  assertEquals(out, `[x](${long}`);
});
