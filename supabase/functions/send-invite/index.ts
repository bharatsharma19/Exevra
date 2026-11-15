/**
 * send-invite entry point: wires real dependencies into the pure handler.
 *
 * POST /functions/v1/send-invite with `Authorization: Bearer <user JWT>` and
 * `{ "group_id": uuid, "email": string, "role"?: "member" | "viewer" }`.
 * See ../README.md for the response contract.
 */
import { createUserClient } from "../_shared/auth.ts";
import { denoEnv, readSupabaseEnv } from "../_shared/env.ts";
import { createLogger } from "../_shared/log.ts";
import { supabaseInviteDb } from "./db.ts";
import { createSendInviteHandler } from "./handler.ts";

const handler = createSendInviteHandler({
  env: denoEnv,
  makeClient: (authorization) =>
    supabaseInviteDb(createUserClient(readSupabaseEnv(denoEnv), authorization)),
  logger: createLogger("send-invite"),
});

Deno.serve(handler);
