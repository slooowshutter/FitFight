import assert from "node:assert/strict";
import { test } from "node:test";
import type { Sql } from "postgres";
import { syncHealthKitCollection } from "./healthkit-collection-supabase-query";
import {
  healthCollectionSessionsPerKind,
  healthKitCollectionMaxBytes,
  healthKitCollectionSyncSchema,
} from "@/lib/types/healthkit/healthkit-collection";

function createDatabaseStub(
  respond: (query: string, values: readonly unknown[]) => unknown[],
) {
  const queries: Array<{ query: string; values: readonly unknown[] }> = [];
  const transaction = ((first: unknown, ...values: unknown[]) => {
    if (!Array.isArray(first) || !("raw" in first)) {
      return { first, values };
    }
    const strings = first as unknown as TemplateStringsArray;
    const query = strings.join("?");
    queries.push({ query, values });
    return Promise.resolve(respond(query, values));
  }) as unknown as Sql;
  Object.assign(transaction, { array: (values: readonly unknown[]) => values });
  const database = Object.assign(
    (() => Promise.reject(new Error("query must run inside a transaction"))) as unknown as Sql,
    {
      begin: async (_options: string, callback: (sql: Sql) => Promise<unknown>) =>
        callback(transaction),
    },
  );
  return { database, queries };
}

const validCollection = {
  complete_through: "2026-08-30T13:53:27.350Z",
  time_zone: "Europe/Paris",
  days: [{
    day: "2026-08-29",
    metric: "active_energy",
    value: 412.5,
    unit: "kcal",
    starts_at: "2026-08-28T22:00:00.000Z",
    ends_at: "2026-08-29T22:00:00.000Z",
  }],
  sessions: [{
    source_uuid: "B4C1285D-0232-4D15-B8CC-1A916BA2BBF7",
    kind: "workout",
    activity_type: "37",
    starts_at: "2026-08-29T07:00:00.000Z",
    ends_at: "2026-08-29T08:00:00.000Z",
    duration_seconds: 3600,
    energy_kcal: 380,
    distance_m: 5000,
  }],
};

test("Apple Health collection accepts statistics and workouts", () => {
  const parsed = healthKitCollectionSyncSchema.parse(validCollection);

  assert.equal(parsed.days[0]?.metric, "active_energy");
  assert.equal(parsed.sessions[0]?.source_uuid, "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7");
  assert.equal(parsed.sessions[0]?.kind, "workout");
});

test("Apple Health collection rejects Steps and raw samples", () => {
  assert.throws(() => healthKitCollectionSyncSchema.parse({
    ...validCollection,
    days: [{ ...validCollection.days[0], metric: "steps", unit: "steps" }],
  }));
  assert.throws(() => healthKitCollectionSyncSchema.parse({
    ...validCollection,
    samples: [{ sample_id: "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7" }],
  }));
});

test("Apple Health collection keeps 2000 sessions per kind under a 4 MiB body", () => {
  assert.equal(healthCollectionSessionsPerKind, 2000);
  assert.equal(healthKitCollectionMaxBytes, 4_000_000);
  const tooManySleep = {
    ...validCollection,
    sessions: Array.from({ length: healthCollectionSessionsPerKind + 1 }, (_, index) => ({
      ...validCollection.sessions[0],
      source_uuid: `b4c1285d-0232-4d15-b8cc-${index.toString(16).padStart(12, "0")}`,
      kind: "sleep",
      activity_type: "asleep",
    })),
  };
  assert.throws(
    () => healthKitCollectionSyncSchema.parse(tooManySleep),
    /too many sessions of one kind/,
  );
});

test("Apple Health collection stores private days and sessions without touching Fight scores", async () => {
  const { database, queries } = createDatabaseStub((query) => {
    if (query.includes("insert into private.health_ingest_state")) {
      return [{
        complete_through: validCollection.complete_through,
        server_now: "2026-08-30T14:00:00.000Z",
      }];
    }
    return [];
  });

  const result = await syncHealthKitCollection(
    "5b2216f4-762d-4890-a516-63046a01df31",
    healthKitCollectionSyncSchema.parse(validCollection),
    database,
  );

  assert.equal(result.synced_days, 1);
  assert.equal(result.synced_sessions, 1);
  assert.ok(queries.some(({ query }) => query.includes("insert into private.health_metric_days")));
  assert.ok(queries.some(({ query }) => query.includes("insert into private.health_sessions")));
  assert.ok(queries.some(({ query }) => query.includes("where private.health_metric_days.finalized_at is null")));
  assert.ok(queries.every(({ query }) => !query.includes("fight_members")));
  assert.ok(queries.every(({ query }) => !query.includes("public.metric_days")));
  assert.ok(queries.every(({ query }) => !query.includes("public.data_sources")));
});

test("Apple Health collection inserts sessions in chunks under the Postgres parameter limit", async () => {
  const { database, queries } = createDatabaseStub((query) => {
    if (query.includes("insert into private.health_ingest_state")) {
      return [{
        complete_through: validCollection.complete_through,
        server_now: "2026-08-30T14:00:00.000Z",
      }];
    }
    return [];
  });
  const sessions = Array.from({ length: 501 }, (_, index) => ({
    ...validCollection.sessions[0],
    source_uuid: `b4c1285d-0232-4d15-b8cc-${index.toString(16).padStart(12, "0")}`,
  }));

  await syncHealthKitCollection(
    "5b2216f4-762d-4890-a516-63046a01df31",
    healthKitCollectionSyncSchema.parse({ ...validCollection, days: [], sessions }),
    database,
  );

  const sessionInserts = queries.filter(({ query }) =>
    query.includes("insert into private.health_sessions")
  );
  assert.equal(sessionInserts.length, 2);
  const firstChunk = sessionInserts[0]?.values[0];
  const secondChunk = sessionInserts[1]?.values[0];
  assert.ok(firstChunk !== null && typeof firstChunk === "object" && "first" in firstChunk);
  assert.ok(secondChunk !== null && typeof secondChunk === "object" && "first" in secondChunk);
  assert.ok(Array.isArray(firstChunk.first) && firstChunk.first.length === 500);
  assert.ok(Array.isArray(secondChunk.first) && secondChunk.first.length === 1);
});

test("Apple Health collection rejects an older complete_through", async () => {
  const { database } = createDatabaseStub((query) => {
    if (query.includes("insert into private.health_ingest_state")) {
      return [];
    }
    return [];
  });

  await assert.rejects(
    syncHealthKitCollection(
      "5b2216f4-762d-4890-a516-63046a01df31",
      healthKitCollectionSyncSchema.parse(validCollection),
      database,
    ),
    /older than current Apple Health collection/,
  );
});

test("Apple Health collection endpoint exposes the authenticated sync route", async () => {
  const route = await import("@/app/api/v1/healthkit/collection/route");

  assert.equal(route.runtime, "nodejs");
  assert.equal(typeof route.POST, "function");
  assert.equal(typeof route.OPTIONS, "function");
});
