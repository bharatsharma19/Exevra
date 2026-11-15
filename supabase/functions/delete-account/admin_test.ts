import { assertEquals } from "jsr:@std/assert@1.0.19";
import { createAdminClient } from "../_shared/auth.ts";
import { mockFetch } from "../_shared/testing.ts";
import { isUserNotFound, supabaseAccountAdmin } from "./admin.ts";

const ENV = {
  url: "https://project.supabase.test",
  anonKey: "anon-test-key",
  serviceRoleKey: "service-role-test-key",
};
const USER_ID = "11111111-1111-4111-8111-111111111111";

Deno.test("prepareAccountDeletion calls the RPC with the service role", async () => {
  using fetchMock = mockFetch(() => new Response(null, { status: 204 }));
  const admin = supabaseAccountAdmin(createAdminClient(ENV));
  assertEquals(await admin.prepareAccountDeletion(USER_ID), { error: null });
  const call = fetchMock.calls[0];
  assertEquals(call.method, "POST");
  assertEquals(call.url, "https://project.supabase.test/rest/v1/rpc/prepare_account_deletion");
  assertEquals(call.headers.get("apikey"), "service-role-test-key");
  assertEquals(JSON.parse(call.body), { p_user_id: USER_ID });
});

Deno.test("prepareAccountDeletion returns database errors", async () => {
  using _fetch = mockFetch(() =>
    Response.json({ code: "42501", message: "permission denied" }, { status: 403 })
  );
  const admin = supabaseAccountAdmin(createAdminClient(ENV));
  const { error } = await admin.prepareAccountDeletion(USER_ID);
  assertEquals(error?.code, "42501");
});

Deno.test("deleteUser hard-deletes through the admin API and maps 404", async () => {
  {
    using fetchMock = mockFetch(() => Response.json({ id: USER_ID }));
    const admin = supabaseAccountAdmin(createAdminClient(ENV));
    assertEquals(await admin.deleteUser(USER_ID), { error: null });
    const call = fetchMock.calls[0];
    assertEquals(call.method, "DELETE");
    assertEquals(call.url, `https://project.supabase.test/auth/v1/admin/users/${USER_ID}`);
    assertEquals(JSON.parse(call.body), { should_soft_delete: false });
  }
  {
    using _fetch = mockFetch(() =>
      Response.json({ code: 404, error_code: "user_not_found", msg: "User not found" }, {
        status: 404,
      })
    );
    const admin = supabaseAccountAdmin(createAdminClient(ENV));
    const { error } = await admin.deleteUser(USER_ID);
    assertEquals(error?.status, 404);
    assertEquals(error?.code, "user_not_found");
    assertEquals(isUserNotFound(error), true);
  }
});

Deno.test("isUserNotFound only matches missing users", () => {
  assertEquals(isUserNotFound(null), false);
  assertEquals(isUserNotFound({ status: 500 }), false);
  assertEquals(isUserNotFound({ status: 404 }), true);
  assertEquals(isUserNotFound({ status: 400, code: "user_not_found" }), true);
});
