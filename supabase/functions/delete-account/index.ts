/**
 * delete-account entry point: wires real dependencies into the pure handler.
 *
 * POST /functions/v1/delete-account with `Authorization: Bearer <user JWT>` and an optional
 * `{ "apple_authorization_code": string }` body. See ../README.md for the response contract.
 */
import { createAdminClient, createUserClient } from "../_shared/auth.ts";
import { denoEnv, readSupabaseAdminEnv, readSupabaseEnv } from "../_shared/env.ts";
import { createLogger } from "../_shared/log.ts";
import { supabaseAccountAdmin } from "./admin.ts";
import { createDeleteAccountHandler } from "./handler.ts";

const handler = createDeleteAccountHandler({
  env: denoEnv,
  makeUserClient: (authorization) => createUserClient(readSupabaseEnv(denoEnv), authorization),
  makeAdmin: () => supabaseAccountAdmin(createAdminClient(readSupabaseAdminEnv(denoEnv))),
  logger: createLogger("delete-account"),
});

Deno.serve(handler);
