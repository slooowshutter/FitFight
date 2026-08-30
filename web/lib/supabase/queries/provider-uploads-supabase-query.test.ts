import assert from "node:assert/strict";
import { test } from "node:test";
import type { Sql } from "postgres";
import { getProviderUploadContext } from "./provider-uploads-supabase-query";

test("provider upload context returns ISO-8601 fight timestamps", async () => {
  const database = (() => Promise.resolve([{
    fight_id: "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7",
    state: "live",
    starts_at: "2026-08-27 16:06:36.729+00",
    ends_at: "2026-09-03 16:06:35.093+00",
  }])) as unknown as Sql;

  const context = await getProviderUploadContext(
    "5b2216f4-762d-4890-a516-63046a01df31",
    database,
    new Date("2026-08-30T13:53:27.350Z"),
  );

  assert.deepEqual(context, {
    server_now: "2026-08-30T13:53:27.350Z",
    fight_windows: [{
      fight_id: "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7",
      state: "live",
      starts_at: "2026-08-27T16:06:36.729Z",
      ends_at: "2026-09-03T16:06:35.093Z",
      cutoff_at: "2026-08-30T13:53:27.350Z",
    }],
  });
});
