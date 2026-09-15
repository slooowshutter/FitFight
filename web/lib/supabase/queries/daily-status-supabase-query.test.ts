import assert from "node:assert/strict";
import { test } from "node:test";
import type { Sql } from "postgres";
import { dailyStatusRecapResponseSchema } from "@/lib/types/notifications/daily-status";
import { enqueueDailyStatusNotifications } from "./daily-status-supabase-query";

test("enqueueDailyStatusNotifications no-ops when OpenRouter is not configured", async () => {
  const previous = process.env.OPENROUTER_API_KEY;
  delete process.env.OPENROUTER_API_KEY;
  const result = await enqueueDailyStatusNotifications(
    new Date("2026-09-11T09:00:00.000Z"),
    Object.assign(() => { throw new Error("database should not be queried"); }, {
      begin: async () => { throw new Error("database should not be queried"); },
    }) as never,
  );
  assert.equal(result.configured, false);
  assert.equal(result.candidates, 0);
  assert.equal(result.enqueued, 0);
  if (previous) {
    process.env.OPENROUTER_API_KEY = previous;
  }
});

test("daily status recap parsing accepts postgres Date values", () => {
  const createdAt = new Date("2026-09-11T09:15:00.000Z");
  const parsed = dailyStatusRecapResponseSchema.parse({
    recap: "You are pulling ahead. Keep moving.",
    sent_at: createdAt.toISOString(),
  });
  assert.equal(parsed.sent_at, "2026-09-11T09:15:00.000Z");
});

test("daily status selects only opted-in users with an authorized active device before calling AI", async (t) => {
  const previousKey = process.env.OPENROUTER_API_KEY;
  process.env.OPENROUTER_API_KEY = "test-key";
  t.after(() => {
    if (previousKey === undefined) delete process.env.OPENROUTER_API_KEY;
    else process.env.OPENROUTER_API_KEY = previousKey;
  });
  let candidateQuery = "";
  const database = ((strings: TemplateStringsArray) => {
    candidateQuery = strings.join("?").replace(/\s+/g, " ").trim();
    return Promise.resolve([]);
  }) as unknown as Sql;
  const remote = t.mock.method(globalThis, "fetch", async () => {
    throw new Error("No eligible devices should reach OpenRouter");
  });

  const result = await enqueueDailyStatusNotifications(new Date("2026-09-15T12:00:00Z"), database);

  assert.match(candidateQuery, /left join private.notification_preferences as preferences on preferences.user_id = member.user_id/);
  assert.match(candidateQuery, /coalesce\(preferences.daily_status, true\)/);
  assert.match(candidateQuery, /join lateral \( select locale from private.device_installations/);
  assert.doesNotMatch(candidateQuery, /left join lateral \( select locale/);
  assert.match(candidateQuery, /device.revoked_at is null and device.permission_status = 'authorized'/);
  assert.equal(result.candidates, 0);
  assert.equal(remote.mock.callCount(), 0);
});
