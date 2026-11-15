/** Minimal Resend client (https://resend.com/docs/api-reference/emails/send-email). */

export const RESEND_EMAILS_URL = "https://api.resend.com/emails";
export const RESEND_TIMEOUT_MS = 10_000;

/** One email to send. */
export interface ResendEmail {
  from: string;
  to: string;
  subject: string;
  html: string;
  text: string;
  /** Sent as `Idempotency-Key` so retries never send twice (Resend keeps keys for 24 h). */
  idempotencyKey: string;
}

/** Outcome of a send attempt. `status` is the HTTP status, or 0 for network/timeout errors. */
export interface ResendResult {
  ok: boolean;
  status: number;
  /** Class name of a thrown error (never its message). */
  error?: string;
}

/** A `fetch`-compatible function (injected in tests). */
export type FetchFn = (input: string, init: RequestInit) => Promise<Response>;

/** The real `fetch`, looked up at call time so tests can replace `globalThis.fetch`. */
export const globalFetch: FetchFn = (
  input: string,
  init: RequestInit,
): Promise<Response> => fetch(input, init);

/** Sends one email. Never throws; only a 2xx response counts as sent. */
export async function sendWithResend(
  apiKey: string,
  email: ResendEmail,
  options: { fetchFn?: FetchFn; timeoutMs?: number } = {},
): Promise<ResendResult> {
  const fetchFn = options.fetchFn ?? globalFetch;
  try {
    const res = await fetchFn(RESEND_EMAILS_URL, {
      method: "POST",
      headers: {
        "authorization": `Bearer ${apiKey}`,
        "content-type": "application/json",
        "idempotency-key": email.idempotencyKey,
      },
      body: JSON.stringify({
        from: email.from,
        to: [email.to],
        subject: email.subject,
        html: email.html,
        text: email.text,
      }),
      signal: AbortSignal.timeout(options.timeoutMs ?? RESEND_TIMEOUT_MS),
    });
    await res.body?.cancel().catch(() => {});
    return { ok: res.status >= 200 && res.status < 300, status: res.status };
  } catch (err) {
    return {
      ok: false,
      status: 0,
      error: err instanceof Error ? err.name : typeof err,
    };
  }
}
