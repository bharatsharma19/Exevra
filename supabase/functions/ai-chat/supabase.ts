/**
 * Adapts a caller-scoped supabase-js client to the narrow {@link AiChatClient} port the handler
 * uses. Keeping the port small lets tests use plain fake objects.
 */
import { createUserClient, type GetUserResult, type SupabaseClient } from "../_shared/auth.ts";
import type { SupabaseEnv } from "../_shared/env.ts";
import type { AiChatClient, DbResult } from "./handler.ts";

/** Wraps `client` (which must carry the caller's Authorization header). */
export function aiChatClient(client: SupabaseClient): AiChatClient {
  return {
    auth: {
      getUser: async (jwt?: string): Promise<GetUserResult> =>
        (await client.auth.getUser(jwt)) as GetUserResult,
    },
    rpc: async (
      fn: string,
      args: Record<string, unknown>,
    ): Promise<DbResult> => {
      const { data, error } = await client.rpc(fn, args);
      return { data, error };
    },
    readAiConsent: async (userId: string): Promise<DbResult> => {
      const { data, error } = await client
        .from("profiles")
        .select("ai_consent")
        .eq("id", userId)
        .maybeSingle();
      return { data, error };
    },
  };
}

/** Factory for the handler: a user-scoped client per request (RLS applies). */
export function aiChatClientFactory(
  env: SupabaseEnv,
): (authorization: string) => AiChatClient {
  return (authorization) => aiChatClient(createUserClient(env, authorization));
}
