import { assertEquals } from "jsr:@std/assert@1.0.19";
import type { SupabaseClient } from "../_shared/auth.ts";
import { aiChatClient } from "./supabase.ts";

Deno.test("aiChatClient reads only the caller's ai_consent and forwards RPCs unchanged", async () => {
  const calls: string[] = [];
  const query = {
    select(columns: string) {
      calls.push(`select:${columns}`);
      return query;
    },
    eq(column: string, value: string) {
      calls.push(`eq:${column}=${value}`);
      return query;
    },
    maybeSingle() {
      calls.push("maybeSingle");
      return Promise.resolve({ data: { ai_consent: true }, error: null });
    },
  };
  const fake = {
    auth: {
      getUser: (jwt?: string) => {
        calls.push(`getUser:${jwt}`);
        return Promise.resolve({ data: { user: { id: "u1" } }, error: null });
      },
    },
    from(table: string) {
      calls.push(`from:${table}`);
      return query;
    },
    rpc(fn: string, args: Record<string, unknown>) {
      calls.push(`rpc:${fn}:${JSON.stringify(args)}`);
      return Promise.resolve({ data: "id-1", error: null, count: null, status: 200 });
    },
  };
  const client = aiChatClient(fake as unknown as SupabaseClient);

  assertEquals((await client.auth.getUser("t")).data.user?.id, "u1");
  assertEquals(await client.readAiConsent("u1"), { data: { ai_consent: true }, error: null });
  assertEquals(await client.rpc("consume_ai_quota", { p_daily_limit: 50 }), {
    data: "id-1",
    error: null,
  });
  assertEquals(calls, [
    "getUser:t",
    "from:profiles",
    "select:ai_consent",
    "eq:id=u1",
    "maybeSingle",
    'rpc:consume_ai_quota:{"p_daily_limit":50}',
  ]);
});
