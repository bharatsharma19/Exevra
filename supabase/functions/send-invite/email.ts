/**
 * Invitation email template (HTML + plain text).
 *
 * Every value interpolated into the HTML goes through the escaping `html` tag, including the
 * link and the recipient's address. Names are first flattened to one short line so they cannot
 * inject headers or break the layout.
 */
import { html, type SafeHtml } from "../_shared/html.ts";
import { toSingleLine } from "../_shared/html.ts";
import type { InviteRole } from "./db.ts";

/** Longest inviter/group name shown in the email (matches the database limit of 60). */
export const MAX_NAME_CHARS = 60;

/** Used when the inviter's display name cannot be read. */
export const FALLBACK_INVITER = "Someone";
/** Used when the group name cannot be read. */
export const FALLBACK_GROUP = "a group";

/** Values that go into the email. All strings are untrusted. */
export interface InviteEmailInput {
  inviterName: string | null;
  groupName: string | null;
  role: InviteRole;
  recipientEmail: string;
  /** Absolute invitation link built from APP_BASE_URL. */
  link: string;
  /** Whole days until the invitation expires (at least 1). */
  expiresInDays: number;
}

/** A rendered email. */
export interface InviteEmail {
  subject: string;
  html: string;
  text: string;
}

const ROLE_COPY: Readonly<Record<InviteRole, string>> = {
  member: "As a member you can add shared expenses, see balances and settle up.",
  viewer: "As a viewer you can see the group's expenses and balances.",
};

/**
 * Text that mail clients may turn into a link: a URL scheme, `www.`, an email address or a
 * domain-like `word.tld`. Checked after NFKC normalisation so fullwidth dots and letters count.
 */
const URL_LIKE = /[a-z][a-z0-9+.-]*:\/\/|www\.|\S@\S|[\p{L}\p{N}_-]\.\p{L}{2,}/iu;

/** True when a (cleaned) name could be shown as a link or read as an address by a mail client. */
export function looksLikeUrl(text: string): boolean {
  return URL_LIKE.test(toSingleLine(text, 1000).normalize("NFKC"));
}

/**
 * Flattens a name to one short line. Names that look like URLs, domains or email addresses use
 * the neutral fallback instead, so an invitation sent from Exevra's domain cannot carry a
 * clickable phishing link or a fake "verify at ..." instruction in the inviter or group name.
 */
function cleanName(value: string | null, fallback: string): string {
  const clean = value === null ? "" : toSingleLine(value, MAX_NAME_CHARS);
  if (clean === "" || looksLikeUrl(clean)) return fallback;
  return clean;
}

function expiryPhrase(days: number): string {
  const whole = Math.max(1, Math.round(days));
  return whole === 1 ? "1 day" : `${whole} days`;
}

/** Renders the subject, HTML body and plain-text body for an invitation. */
export function renderInviteEmail(input: InviteEmailInput): InviteEmail {
  const inviter = cleanName(input.inviterName, FALLBACK_INVITER);
  const group = cleanName(input.groupName, FALLBACK_GROUP);
  const email = toSingleLine(input.recipientEmail, 254);
  const link = input.link;
  const roleCopy = ROLE_COPY[input.role];
  const expires = expiryPhrase(input.expiresInDays);

  const subject = toSingleLine(
    `${inviter} invited you to ${group} on Exevra`,
    200,
  );

  const body: SafeHtml = html`
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light">
        <title>${subject}</title>
      </head>
      <body
        style="margin:0;padding:0;background:#f4f5f7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1f2933;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
          style="background:#f4f5f7;padding:24px 12px;">
          <tr>
            <td align="center">
              <table role="presentation" width="100%" cellpadding="0"
                cellspacing="0"
                style="max-width:520px;background:#ffffff;border-radius:12px;padding:32px 28px;">
                <tr>
                  <td>
                    <p
                      style="margin:0 0 8px;font-size:14px;color:#52606d;">Exevra</p>
                    <h1
                      style="margin:0 0 16px;font-size:22px;line-height:1.3;">You're invited to join ${group}</h1>
                    <p
                      style="margin:0 0 12px;font-size:16px;line-height:1.5;"><strong>${inviter}</strong> invited you to join <strong>${group}</strong> on Exevra, the app for tracking expenses and splitting costs with friends.</p>
                    <p
                      style="margin:0 0 24px;font-size:16px;line-height:1.5;">${roleCopy}</p>
                    <p
                      style="margin:0 0 24px;"><a href="${link}" style="display:inline-block;background:#2f6fed;color:#ffffff;text-decoration:none;font-weight:600;font-size:16px;padding:12px 24px;border-radius:8px;">Accept invitation</a></p>
                    <p
                      style="margin:0 0 12px;font-size:14px;line-height:1.5;color:#52606d;">Open this link on your phone and sign in to Exevra with <strong>${email}</strong>. The invitation only works for this email address and expires in ${expires}.</p>
                    <p
                      style="margin:0 0 12px;font-size:14px;line-height:1.5;color:#52606d;">If the button doesn't work, copy this link into your browser:<br><span style="word-break:break-all;">${link}</span></p>
                    <p
                      style="margin:0;font-size:14px;line-height:1.5;color:#52606d;">If you weren't expecting this invitation, you can ignore this email.</p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </body>
    </html>
  `;

  const text = [
    `${inviter} invited you to join ${group} on Exevra, the app for tracking expenses and splitting costs with friends.`,
    "",
    roleCopy,
    "",
    "Accept the invitation:",
    link,
    "",
    `Open this link on your phone and sign in to Exevra with ${email}. The invitation only works for this email address and expires in ${expires}.`,
    "",
    "If you weren't expecting this invitation, you can ignore this email.",
    "",
  ].join("\n");

  return { subject, html: body.value, text };
}
