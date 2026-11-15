/**
 * Privileged steps of account deletion, behind a port so the handler can be tested with fakes.
 * The real adapter uses a service-role client, which is created only after the caller's JWT has
 * been verified.
 */
import type { SupabaseClient } from "../_shared/auth.ts";
import type { PgErrorLike } from "../_shared/http.ts";

/** Structural subset of a supabase-js `AuthError`. */
export interface AuthErrorLike {
  status?: number;
  code?: string;
  name?: string;
}

/** The two privileged operations account deletion needs. */
export interface AccountAdmin {
  /**
   * Runs `prepare_account_deletion(p_user_id)`: hands group admin rights on, anonymises shared
   * history and deletes personal data. Idempotent.
   */
  prepareAccountDeletion(userId: string): Promise<{ error: PgErrorLike | null }>;
  /** Hard-deletes the auth user. */
  deleteUser(userId: string): Promise<{ error: AuthErrorLike | null }>;
}

/** True when an auth admin error means the user is already gone. */
export function isUserNotFound(error: AuthErrorLike | null | undefined): boolean {
  return !!error && (error.code === "user_not_found" || error.status === 404);
}

/** Adapts a service-role supabase-js client to {@link AccountAdmin}. */
export function supabaseAccountAdmin(client: SupabaseClient): AccountAdmin {
  return {
    async prepareAccountDeletion(userId) {
      try {
        const { error } = await client.rpc("prepare_account_deletion", { p_user_id: userId });
        return { error: error ?? null };
      } catch {
        return { error: { code: "fetch_failed", message: "fetch_failed" } };
      }
    },
    async deleteUser(userId) {
      try {
        const { error } = await client.auth.admin.deleteUser(userId);
        if (!error) return { error: null };
        const code = (error as { code?: unknown }).code;
        return {
          error: {
            status: typeof error.status === "number" ? error.status : undefined,
            code: typeof code === "string" ? code : undefined,
            name: error.name,
          },
        };
      } catch (err) {
        return { error: { status: 0, name: err instanceof Error ? err.name : "Error" } };
      }
    },
  };
}
