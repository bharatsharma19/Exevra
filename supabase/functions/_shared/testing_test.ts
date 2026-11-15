import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.19";
import { fakeTimers, mockFetch } from "./testing.ts";

Deno.test("fakeTimers fires timeouts and intervals in order", () => {
  const timers = fakeTimers(1000);
  const fired: string[] = [];
  timers.setTimeout(() => fired.push(`t@${timers.clock.now()}`), 50);
  const interval = timers.setInterval(() => fired.push(`i@${timers.clock.now()}`), 20);
  const cancelled = timers.setTimeout(() => fired.push("never"), 10);
  timers.clearTimeout(cancelled);
  timers.tick(60);
  timers.clearInterval(interval);
  timers.tick(100);
  assertEquals(fired, ["i@1020", "i@1040", "t@1050", "i@1060"]);
  assertEquals(timers.clock.now(), 1160);
  assertEquals(timers.pending(), 0);
});

Deno.test("mockFetch records requests and restores fetch", async () => {
  const original = globalThis.fetch;
  {
    using mock = mockFetch((req) => new Response(`echo:${req.body}`));
    const res = await fetch("https://api.example.test/v1", {
      method: "POST",
      headers: { "x-api-key": "test" },
      body: "hi",
    });
    assertEquals(await res.text(), "echo:hi");
    assertEquals(mock.calls.length, 1);
    assertEquals(mock.calls[0].method, "POST");
    assertEquals(mock.calls[0].headers.get("x-api-key"), "test");

    const controller = new AbortController();
    controller.abort();
    await assertRejects(() => fetch("https://api.example.test", { signal: controller.signal }));
  }
  assertEquals(globalThis.fetch, original);
});
