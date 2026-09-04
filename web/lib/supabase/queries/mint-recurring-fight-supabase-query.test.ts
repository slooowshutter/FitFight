import assert from "node:assert/strict";
import { test } from "node:test";
import { rollingWindow } from "@/lib/domain/fights/join-code";
import { mintNextRecurringFight } from "./mint-recurring-fight-supabase-query";

type Row = Record<string, unknown>;

function createAdminFake(fights: Row[], series: Row[]) {
  return {
    from(table: string) {
      const filters: Array<[string, unknown]> = [];
      const builder = {
        select() {
          return builder;
        },
        insert() {
          return builder;
        },
        update() {
          return builder;
        },
        eq(column: string, value: unknown) {
          filters.push([column, value]);
          return builder;
        },
        is() {
          return builder;
        },
        maybeSingle() {
          const rows = table === "fights" ? fights : table === "fight_series" ? series : [];
          const found = rows.find((row) => filters.every(([column, value]) => row[column] === value)) ?? null;
          return Promise.resolve({ data: found, error: null });
        },
        single() {
          return builder.maybeSingle();
        },
        then(resolve: (value: { data: null; error: null }) => unknown) {
          return Promise.resolve(resolve({ data: null, error: null }));
        },
      };
      return builder;
    },
  };
}

test("mint reuses the existing row for the same series window", async () => {
  const previous = {
    id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    series_id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    starts_at: "2026-09-01T12:00:00.000Z",
    ends_at: "2026-09-08T12:00:00.000Z",
  };
  const window = rollingWindow(previous.starts_at, previous.ends_at);
  const existing = {
    id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
    series_id: previous.series_id,
    starts_at: window.startsAt,
  };
  const admin = createAdminFake(
    [previous, existing],
    [{
      id: previous.series_id,
      recurring: true,
      paused_at: null,
      current_fight_id: previous.id,
    }],
  );

  const first = await mintNextRecurringFight(
    previous.id,
    admin as never,
    new Date("2026-09-08T12:00:01.000Z"),
  );
  const second = await mintNextRecurringFight(
    previous.id,
    admin as never,
    new Date("2026-09-08T12:00:01.000Z"),
  );
  assert.equal(first, existing.id);
  assert.equal(second, existing.id);
});
