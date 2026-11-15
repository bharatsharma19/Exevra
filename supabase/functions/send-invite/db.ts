/**
 * Database access for send-invite, behind a small port so the handler can be tested with fakes.
 *
 * Every call runs as the caller (anon key + caller JWT), so RLS and the RPC's own admin and
 * rate-limit checks apply. The service role is never used here.
 */
import type { AuthCapableClient, GetUserResult, SupabaseClient } from "../_shared/auth.ts";
import { isRecord, type PgErrorLike } from "../_shared/http.ts";

/** Roles an invitation may grant. Admin is only ever reached via transfer_admin. */
export type InviteRole = "member" | "viewer";

/** Row returned once by `create_group_invitation`. The raw token is never stored server-side. */
export interface CreatedInvitation {
  invitationId: string;
  token: string;
  /** ISO timestamp, or null when the RPC did not return one. */
  expiresAt: string | null;
}

/** Result of {@link InviteDb.createInvitation}: data or a Postgres/PostgREST error. */
export type CreateInvitationResult =
  | { data: CreatedInvitation; error: null }
  | { data: null; error: PgErrorLike };

/** What the handler needs from the database. */
export interface InviteDb extends AuthCapableClient {
  createInvitation(
    groupId: string,
    email: string,
    role: InviteRole,
  ): Promise<CreateInvitationResult>;
  /** The group's name, or null if it cannot be read. Never throws. */
  getGroupName(groupId: string): Promise<string | null>;
  /** The caller's own display name, or null if it cannot be read. Never throws. */
  getDisplayName(userId: string): Promise<string | null>;
}

/** Upper bound for each name lookup. */
export const NAME_LOOKUP_TIMEOUT_MS = 3000;

const MALFORMED: PgErrorLike = {
  code: "malformed_response",
  message: "malformed_response",
};

/** Parses the RPC payload (`RETURNS TABLE` arrives as an array with one row). */
export function parseCreatedInvitation(
  data: unknown,
): CreatedInvitation | null {
  const row = Array.isArray(data) ? data[0] : data;
  if (!isRecord(row)) return null;
  const { invitation_id: invitationId, token, expires_at: expiresAt } = row;
  if (typeof invitationId !== "string" || invitationId === "") return null;
  if (typeof token !== "string" || token === "") return null;
  return {
    invitationId,
    token,
    expiresAt: typeof expiresAt === "string" ? expiresAt : null,
  };
}

async function readSingleString(
  query: PromiseLike<{ data: unknown; error: unknown }>,
  column: string,
): Promise<string | null> {
  try {
    const { data, error } = await query;
    if (error || !isRecord(data)) return null;
    const value = data[column];
    return typeof value === "string" ? value : null;
  } catch {
    return null;
  }
}

/** Adapts a caller-scoped supabase-js client to {@link InviteDb}. */
export function supabaseInviteDb(client: SupabaseClient): InviteDb {
  return {
    auth: {
      getUser: (jwt?: string): Promise<GetUserResult> => client.auth.getUser(jwt),
    },
    async createInvitation(groupId, email, role) {
      try {
        const { data, error } = await client.rpc("create_group_invitation", {
          p_group_id: groupId,
          p_email: email,
          p_role: role,
        });
        if (error) return { data: null, error };
        const parsed = parseCreatedInvitation(data);
        return parsed ? { data: parsed, error: null } : { data: null, error: MALFORMED };
      } catch {
        return {
          data: null,
          error: { code: "fetch_failed", message: "fetch_failed" },
        };
      }
    },
    // Names only decorate the email, so these lookups fail fast: no retries, short timeout.
    getGroupName: (groupId) =>
      readSingleString(
        client.from("groups").select("name").eq("id", groupId)
          .abortSignal(AbortSignal.timeout(NAME_LOOKUP_TIMEOUT_MS)).maybeSingle().retry(false),
        "name",
      ),
    getDisplayName: (userId) =>
      readSingleString(
        client.from("profiles").select("display_name").eq("id", userId)
          .abortSignal(AbortSignal.timeout(NAME_LOOKUP_TIMEOUT_MS)).maybeSingle().retry(false),
        "display_name",
      ),
  };
}
