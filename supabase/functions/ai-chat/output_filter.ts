/**
 * Streaming output filter for model text. The spending data in the prompt includes strings other
 * people wrote (group expense titles, group names), so a prompt injection could make the model
 * emit a Markdown image whose URL carries the user's data; a renderer that loads images would
 * send it out without a click. This filter makes sure no image syntax reaches the app:
 *
 * - inline and reference images (`![alt](url)`, `![alt][ref]`) become their alt text;
 * - any other `![` loses its `!` (so shortcut reference images such as `![ref]` cannot render);
 * - HTML tags that fetch or embed content (`<img>`, `<image>`, `<picture>`, `<source>`,
 *   `<iframe>`, `<svg>`, `<object>`, `<embed>`, `<link>`, `<video>`, `<audio>`; see
 *   {@link BLOCKED_TAGS}) are removed, opening and closing tags alike.
 *
 * Removing a construct must never splice its neighbours into a new one (`!<img>[a](url)` must not
 * become `![a](url)`), so a removed tag or a dropped `!`/`<` leaves a space behind, and a final
 * guard checks the emitted stream itself, across chunks: it never emits `!` directly followed by
 * `[` (a space goes between them), and a `<` that would start a blocked tag (`<img`, `</svg`,
 * `< img`) is sent as {@link NEUTRAL_LT} instead.
 *
 * Text is held back only while a possible image is still incomplete at a chunk boundary, and at
 * most {@link MAX_HOLD_CHARS} characters; past that (or at the end of the stream) the construct
 * is neutralised instead of waiting. The app must still render with images disabled (README).
 */

/** Longest stretch of text held back while waiting for an image construct to complete. */
export const MAX_HOLD_CHARS = 2048;

/** A stateful filter for one answer. */
export interface OutputFilter {
  /** Adds a chunk and returns the text that is safe to send now (may be empty). */
  push(text: string): string;
  /** Returns whatever is still held back, neutralised. Call once at the end of the answer. */
  flush(): string;
}

type Match =
  | { kind: "image"; alt: string; end: number }
  | { kind: "tag"; end: number }
  | { kind: "none" }
  | { kind: "incomplete" };

/** Index of the bracket closing the one at `open`, honouring nesting and backslash escapes. */
function closing(
  s: string,
  open: number,
  opener: string,
  closer: string,
): number {
  let depth = 0;
  for (let i = open; i < s.length; i++) {
    const ch = s[i];
    if (ch === "\\") {
      i++;
    } else if (ch === opener) {
      depth++;
    } else if (ch === closer) {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

/** Matches a Markdown image starting at `s[i] === "!"`, `s[i + 1] === "["`. */
function matchImage(s: string, i: number): Match {
  const close = closing(s, i + 1, "[", "]");
  if (close < 0 || close + 1 >= s.length) return { kind: "incomplete" };
  const next = s[close + 1];
  let end: number;
  if (next === "(") {
    end = closing(s, close + 1, "(", ")");
  } else if (next === "[") {
    end = closing(s, close + 1, "[", "]");
  } else {
    return { kind: "none" };
  }
  if (end < 0) return { kind: "incomplete" };
  return { kind: "image", alt: s.slice(i + 2, close), end: end + 1 };
}

/**
 * HTML elements that load a URL by themselves (or embed a document that can), removed wherever
 * they appear, opening and closing tags alike. Other tags and plain `<` (as in `<5 items` or
 * `a < b`) are left alone; the app never renders raw HTML anyway (README).
 */
export const BLOCKED_TAGS: ReadonlySet<string> = new Set([
  "img",
  "image",
  "picture",
  "source",
  "iframe",
  "svg",
  "object",
  "embed",
  "link",
  "video",
  "audio",
]);
const TAG_BOUNDARY = /[\s/>]/;
const LETTER = /[A-Za-z]/;

/**
 * Index of the `>` ending a tag whose attributes start at `from`, or -1 if not seen yet. A `>`
 * inside a quoted attribute value (`alt="a>b"`) does not end the tag.
 */
function tagEnd(s: string, from: number): number {
  for (let i = from; i < s.length; i++) {
    const ch = s[i];
    if (ch === ">") return i;
    if (ch !== "=") continue;
    let j = i + 1;
    while (j < s.length && /\s/.test(s[j])) j++;
    if (j >= s.length) return -1;
    const quote = s[j];
    if (quote !== '"' && quote !== "'") continue;
    const close = s.indexOf(quote, j + 1);
    if (close < 0) return -1;
    i = close;
  }
  return -1;
}

/** Matches an opening or closing {@link BLOCKED_TAGS} tag starting at `s[i] === "<"`. */
function matchBlockedTag(s: string, i: number): Match {
  let start = i + 1;
  if (s[start] === "/") start++;
  let end = start;
  while (end < s.length && LETTER.test(s[end])) end++;
  const name = s.slice(start, end).toLowerCase();
  if (end >= s.length) {
    // The name may still be growing: wait only if it can become a blocked tag.
    for (const tag of BLOCKED_TAGS) {
      if (tag.startsWith(name)) return { kind: "incomplete" };
    }
    return { kind: "none" };
  }
  if (!BLOCKED_TAGS.has(name) || !TAG_BOUNDARY.test(s[end])) {
    return { kind: "none" };
  }
  const close = tagEnd(s, end);
  return close < 0 ? { kind: "incomplete" } : { kind: "tag", end: close + 1 };
}

/** Filters a complete string (also used for alt text, which may itself contain images). */
export function stripImages(text: string): string {
  const filter = createOutputFilter();
  return filter.push(text) + filter.flush();
}

/**
 * Sent instead of a `<` that would start a blocked tag in the output ("‹", U+2039). It is not
 * whitespace, `/` or a letter, and has no compatibility decomposition back to `<`.
 */
export const NEUTRAL_LT = "\u2039";

const WORD = /[A-Za-z0-9_]/;
const SPACE_OR_SLASH = /[\s/]/;
const LONGEST_BLOCKED_TAG = Math.max(
  ...[...BLOCKED_TAGS].map((tag) => tag.length),
);

/**
 * Decides whether the `<` at `s[i]` (in the output stream) would start a blocked tag. Stricter
 * than HTML on purpose: whitespace and `/` between `<` and the name are skipped (`< img`,
 * `</ svg`), and the name is the whole word that follows, so `<imgx` and `<img2` are safe.
 */
function classifyAngle(
  s: string,
  i: number,
  final: boolean,
): "safe" | "unsafe" | "wait" {
  let j = i + 1;
  while (j < s.length && SPACE_OR_SLASH.test(s[j])) j++;
  if (j >= s.length) return final ? "safe" : "wait";
  let k = j;
  while (k < s.length && k - j <= LONGEST_BLOCKED_TAG && WORD.test(s[k])) k++;
  const word = s.slice(j, k).toLowerCase();
  if (k >= s.length && !final) {
    for (const tag of BLOCKED_TAGS) {
      if (tag.startsWith(word)) return "wait";
    }
    return "safe";
  }
  return BLOCKED_TAGS.has(word) && !(k < s.length && WORD.test(s[k])) ? "unsafe" : "safe";
}

/**
 * The last line of defence, applied to everything the filter emits: whatever the removals
 * produced, the stream never contains `![` or a `<` that starts a blocked tag. Holds back from a
 * `<` only until the following word is known (at most {@link MAX_HOLD_CHARS} characters).
 */
function createGuard(): (text: string, final: boolean) => string {
  let held = "";
  let last = "";
  return (text, final) => {
    const s = held + text;
    held = "";
    let out = "";
    for (let i = 0; i < s.length; i++) {
      let ch = s[i];
      if (ch === "<") {
        const verdict = classifyAngle(s, i, final);
        if (verdict === "wait" && s.length - i <= MAX_HOLD_CHARS) {
          held = s.slice(i);
          break;
        }
        if (verdict !== "safe") ch = NEUTRAL_LT;
      } else if (ch === "[" && last === "!") {
        out += " ";
      }
      out += ch;
      last = ch;
    }
    return out;
  };
}

/** Creates an {@link OutputFilter}. */
export function createOutputFilter(): OutputFilter {
  let pending = "";
  /** Last character this stage produced, across chunks ("" before any). */
  let lastChar = "";
  const guard = createGuard();

  const run = (final: boolean): string => {
    const s = pending;
    let out = "";
    // Leaves a space where something was removed, so the text around it cannot join up.
    const separate = () => {
      const prev = out.length > 0 ? out[out.length - 1] : lastChar;
      if (prev !== "" && !/\s/.test(prev)) out += " ";
    };
    let i = 0;
    while (i < s.length) {
      const ch = s[i];
      if (ch !== "!" && ch !== "<") {
        out += ch;
        i++;
        continue;
      }
      // Hold back while the construct may still complete, within the hold limit.
      const canWait = !final && s.length - i <= MAX_HOLD_CHARS;
      if (ch === "!") {
        if (i + 1 >= s.length) {
          if (canWait) break;
          out += ch;
          i++;
          continue;
        }
        if (s[i + 1] !== "[") {
          out += ch;
          i++;
          continue;
        }
        const match = matchImage(s, i);
        if (match.kind === "incomplete" && canWait) break;
        if (match.kind === "image") {
          const alt = stripImages(match.alt);
          if (alt === "") separate();
          out += alt;
          i = match.end;
          continue;
        }
        // Not an inline/reference image (or it never completed): drop the "!" so it cannot
        // render as an image, and keep the rest as ordinary text.
        separate();
        i++;
        continue;
      }
      const match = matchBlockedTag(s, i);
      if (match.kind === "incomplete" && canWait) break;
      if (match.kind === "tag") {
        separate();
        i = match.end;
        continue;
      }
      if (match.kind === "incomplete") {
        // A blocked tag that never closed: drop the "<" so it cannot form a tag.
        separate();
        i++;
        continue;
      }
      out += ch;
      i++;
    }
    pending = s.slice(i);
    if (out.length > 0) lastChar = out[out.length - 1];
    return guard(out, final);
  };

  return {
    push(text) {
      pending += text;
      return run(false);
    },
    flush() {
      const out = run(true);
      pending = "";
      return out;
    },
  };
}
