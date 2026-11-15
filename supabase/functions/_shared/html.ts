/**
 * HTML escaping for emails. Every user-controlled value (names, group names, emails) must go
 * through {@link escapeHtml} or the {@link html} template tag.
 */

const ESCAPES: Readonly<Record<string, string>> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
  "`": "&#96;",
  "=": "&#61;",
};

/**
 * Escapes text for use in HTML element content or a quoted attribute. `null`/`undefined` become
 * an empty string; other values are converted with `String()`.
 */
export function escapeHtml(value: unknown): string {
  if (value === null || value === undefined) return "";
  return String(value).replace(/[&<>"'`=]/g, (ch) => ESCAPES[ch]);
}

/** A string already known to be safe HTML. Create it only via {@link html} or {@link trustedHtml}. */
export class SafeHtml {
  readonly value: string;

  constructor(value: string) {
    this.value = value;
  }

  toString(): string {
    return this.value;
  }
}

/** Marks a constant, developer-written string as safe HTML. Never pass user input. */
export function trustedHtml(raw: string): SafeHtml {
  return new SafeHtml(raw);
}

function interpolate(value: unknown): string {
  if (value instanceof SafeHtml) return value.value;
  if (Array.isArray(value)) return value.map(interpolate).join("");
  return escapeHtml(value);
}

/**
 * Template tag that escapes every interpolated value unless it is a {@link SafeHtml} (arrays are
 * escaped item by item and joined). Example: html`<p>Hi ${name}</p>`.
 */
export function html(strings: TemplateStringsArray, ...values: unknown[]): SafeHtml {
  let out = strings[0];
  for (let i = 0; i < values.length; i++) out += interpolate(values[i]) + strings[i + 1];
  return new SafeHtml(out);
}

/**
 * Normalises user text for single-line contexts such as email subjects and plain-text bodies:
 * removes control characters, collapses whitespace (including CR/LF, preventing header
 * injection) and truncates to `maxLength` characters with an ellipsis.
 */
export function toSingleLine(text: string, maxLength: number): string {
  // deno-lint-ignore no-control-regex
  const clean = text.replace(/[\u0000-\u001f\u007f\u2028\u2029]+/g, " ").replace(/\s+/g, " ")
    .trim();
  const chars = Array.from(clean);
  if (chars.length <= maxLength) return clean;
  return `${chars.slice(0, Math.max(0, maxLength - 1)).join("").trimEnd()}…`;
}

/**
 * Returns the normalised URL when it is an absolute `https:` URL without credentials, else
 * `null`. Use before putting any URL in an `href`.
 */
export function safeHttpsUrl(url: string): string | null {
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== "https:" || parsed.username || parsed.password) return null;
    return parsed.href;
  } catch {
    return null;
  }
}
