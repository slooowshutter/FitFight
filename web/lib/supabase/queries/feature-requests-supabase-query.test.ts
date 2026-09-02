import assert from "node:assert/strict";
import { test } from "node:test";
import type { Sql } from "postgres";
import { ApiError } from "@/lib/http";
import {
  createFeatureRequestSchema,
  listFeatureRequestsQuerySchema,
} from "@/lib/types/requests/feature-request";
import {
  blockFeatureRequestAuthor,
  createFeatureRequest,
  listFeatureRequests,
  reportFeatureRequest,
  toggleFeatureRequestVote,
} from "./feature-requests-supabase-query";

const USER_ID = "11111111-1111-4111-8111-111111111111";
const AUTHOR_ID = "22222222-2222-4222-8222-222222222222";
const REQUEST_ID = "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7";

const visibleRow = {
  id: REQUEST_ID,
  kind: "feature",
  status: "open",
  title: "Custom challenge length",
  body: "Let me pick any number of days.",
  created_at: new Date("2026-09-01T12:00:00.000Z"),
  author_user_id: AUTHOR_ID,
  author_handle: "leo",
  author_display_name: "Leo",
  vote_count: 3,
  voted: false,
};

function createDatabaseStub(
  respond: (query: string, values: readonly unknown[]) => unknown[],
) {
  const queries: Array<{ query: string; values: readonly unknown[] }> = [];
  const run = ((first: unknown, ...values: unknown[]) => {
    const strings = first as TemplateStringsArray;
    const query = strings.join("?").replace(/\s+/g, " ").trim();
    queries.push({ query, values });
    return Promise.resolve(respond(query, values));
  }) as unknown as Sql;
  const database = Object.assign(run, {
    begin: async (_options: string, callback: (sql: Sql) => Promise<unknown>) =>
      callback(run),
  });
  return { database, queries };
}

test("create feature request schema trims and rejects empty copy", () => {
  const parsed = createFeatureRequestSchema.parse({
    kind: "bug",
    title: "  Chart is blank  ",
    body: "  Pull to refresh left the days empty.  ",
  });
  assert.equal(parsed.title, "Chart is blank");
  assert.equal(parsed.body, "Pull to refresh left the days empty.");
  assert.throws(() =>
    createFeatureRequestSchema.parse({ kind: "feature", title: "   ", body: "ok" }),
  );
  assert.throws(() =>
    createFeatureRequestSchema.parse({ kind: "money", title: "Hi", body: "There" }),
  );
});

test("list feature requests query accepts feature, bug, or omitted kind", () => {
  assert.deepEqual(listFeatureRequestsQuerySchema.parse({}), {});
  assert.equal(listFeatureRequestsQuerySchema.parse({ kind: "bug" }).kind, "bug");
  assert.throws(() => listFeatureRequestsQuerySchema.parse({ kind: "top" }));
});

test("listFeatureRequests hides reported, blocked, and hidden rows", async () => {
  const { database, queries } = createDatabaseStub(() => [visibleRow]);
  const items = await listFeatureRequests(USER_ID, "feature", database);

  assert.equal(items[0]?.title, "Custom challenge length");
  assert.equal(items[0]?.author.handle, "leo");
  assert.match(queries[0]?.query ?? "", /hidden_at is null/);
  assert.match(queries[0]?.query ?? "", /feature_request_blocks/);
  assert.match(queries[0]?.query ?? "", /feature_request_reports/);
  assert.equal(queries[0]?.values[0], USER_ID);
  assert.equal(queries[0]?.values.includes("feature"), true);
});

test("createFeatureRequest rejects a sixth post in 24 hours", async () => {
  const { database } = createDatabaseStub((query) => {
    if (query.includes("select count(*)::int as count")) {
      return [{ count: 5 }];
    }
    return [];
  });

  await assert.rejects(
    () =>
      createFeatureRequest(
        USER_ID,
        { kind: "feature", title: "Watch face", body: "Show rank on the watch." },
        database,
      ),
    (error: unknown) =>
      error instanceof ApiError &&
      error.status === 429 &&
      error.message === "You can post 5 requests per day.",
  );
});

test("toggleFeatureRequestVote inserts when the user has not voted", async () => {
  const { database, queries } = createDatabaseStub((query) => {
    if (query.includes("select request_id from public.feature_request_votes")) {
      return [];
    }
    if (query.startsWith("insert into public.feature_request_votes")) {
      return [];
    }
    return [{ ...visibleRow, vote_count: 4, voted: true }];
  });

  const item = await toggleFeatureRequestVote(USER_ID, REQUEST_ID, database);
  assert.equal(item.voted, true);
  assert.equal(item.voteCount, 4);
  const insert = queries.find((entry) =>
    entry.query.startsWith("insert into public.feature_request_votes"),
  );
  assert.match(insert?.query ?? "", /on conflict do nothing/);
});

test("toggleFeatureRequestVote deletes an existing vote", async () => {
  const { database, queries } = createDatabaseStub((query) => {
    if (query.includes("select request_id from public.feature_request_votes")) {
      return [{ request_id: REQUEST_ID }];
    }
    if (query.startsWith("delete from public.feature_request_votes")) {
      return [];
    }
    return [{ ...visibleRow, vote_count: 2, voted: false }];
  });

  const item = await toggleFeatureRequestVote(USER_ID, REQUEST_ID, database);
  assert.equal(item.voted, false);
  assert.equal(
    queries.some((entry) => entry.query.startsWith("delete from public.feature_request_votes")),
    true,
  );
});

test("reportFeatureRequest hides a post after three reports", async () => {
  const { database, queries } = createDatabaseStub((query) => {
    if (query.includes("select count(*)::int as count")) {
      return [{ count: 3 }];
    }
    if (query.startsWith("insert into public.feature_request_reports")) {
      return [];
    }
    if (query.startsWith("update public.feature_requests")) {
      return [];
    }
    return [visibleRow];
  });

  const result = await reportFeatureRequest(USER_ID, REQUEST_ID, database);
  assert.equal(result.reported, true);
  assert.equal(result.hidden, true);
  assert.equal(
    queries.some((entry) => entry.query.startsWith("update public.feature_requests")),
    true,
  );
});

test("reportFeatureRequest rejects reporting your own post", async () => {
  const { database, queries } = createDatabaseStub(() => [
    { ...visibleRow, author_user_id: USER_ID },
  ]);

  await assert.rejects(
    () => reportFeatureRequest(USER_ID, REQUEST_ID, database),
    /You cannot report your own request/,
  );
  assert.equal(
    queries.some((entry) => entry.query.startsWith("insert into public.feature_request_reports")),
    false,
  );
});

test("blockFeatureRequestAuthor records a block of the author", async () => {
  const { database, queries } = createDatabaseStub((query) => {
    if (query.startsWith("insert into public.feature_request_blocks")) {
      return [];
    }
    return [visibleRow];
  });

  const result = await blockFeatureRequestAuthor(USER_ID, REQUEST_ID, database);
  assert.equal(result.blocked, true);
  assert.equal(queries.at(-1)?.values[0], USER_ID);
  assert.equal(queries.at(-1)?.values[1], AUTHOR_ID);
});
