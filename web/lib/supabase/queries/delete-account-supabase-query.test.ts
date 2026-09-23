import assert from "node:assert/strict";
import { test } from "node:test";
import type { Sql } from "postgres";
import { deleteAccount } from "./delete-account-supabase-query";

process.env.NEXT_PUBLIC_SUPABASE_URL = "https://example.supabase.co";
process.env.SUPABASE_SECRET_KEY = "test-secret-key";

function createDatabaseStub(options: {
    profileExists: boolean;
    mediaPaths?: string[];
}) {
    const queries: string[] = [];
    const query = ((first: TemplateStringsArray, ..._values: unknown[]) => {
        const sql = first.join("?").replace(/\s+/g, " ").trim();
        queries.push(sql);
        if (sql.includes("select id as user_id from public.profiles")) {
            return Promise.resolve(
                options.profileExists ? [{ user_id: "user-id" }] : [],
            );
        }
        if (sql.includes("select object_path from public.media_objects")) {
            return Promise.resolve(
                (options.mediaPaths ?? []).map((object_path) => ({
                    object_path,
                })),
            );
        }
        return Promise.resolve([]);
    }) as unknown as Sql;
    Object.assign(query, {
        array: (values: readonly unknown[]) => values,
    });
    const database = Object.assign(query, {
        begin: async (
            _options: string,
            callback: (sql: Sql) => Promise<unknown>,
        ) => callback(query),
    });
    return { database, queries };
}

test("account deletion removes owned Fights and every user-owned row before the auth user", async () => {
    const { database, queries } = createDatabaseStub({ profileExists: true });

    const appleAuthorizationRevoked = await deleteAccount("user-id", database);

    assert.equal(appleAuthorizationRevoked, false);
    for (const table of [
        "public.feedback_votes",
        "public.feedback_comments",
        "public.feedback_posts",
        "private.feedback_post_reports",
        "private.feedback_blocks",
        "private.fight_post_reports",
        "private.fight_post_comment_reports",
        "private.feed_blocks",
        "public.fight_post_comments",
        "public.fight_post_reactions",
        "public.fight_post_tags",
        "public.fight_posts",
        "public.media_objects",
        "public.fights",
        "public.fight_series",
        "public.fight_series_members",
        "private.fight_score_snapshots",
        "private.activity_metrics",
        "private.activity_raw",
        "private.metric_observations",
        "private.provider_events",
        "private.provider_uploads",
        "private.healthkit_step_source_days",
        "private.healthkit_step_sample_deletions",
        "private.healthkit_step_samples",
        "private.healthkit_step_syncs",
        "private.healthkit_activity_days",
        "private.healthkit_workouts",
        "public.metric_days",
        "public.step_days",
        "public.fight_members",
        "public.fight_invites",
        "public.friendships",
        "public.data_sources",
        "private.fight_join_attempts",
        "auth.sessions",
        "auth.refresh_tokens",
        "auth.identities",
        "auth.users",
    ]) {
        assert.ok(
            queries.some((query) => query.includes(`delete from ${table}`)),
            table,
        );
    }
    assert.ok(
        queries.some((query) => query.includes("update public.fight_series")),
    );
    assert.ok(
        queries.some((query) =>
            query.includes("public.fights where owner_id = ?"),
        ),
    );
    assert.ok(
        queries.some((query) =>
            query.includes("public.fight_members where user_id = ?"),
        ),
    );
    assert.equal(
        queries.some((query) => query.includes("update public.profiles")),
        false,
    );
    assert.equal(
        queries.some((query) => query.includes("update auth.users")),
        false,
    );
    assert.equal(queries.at(-1), "delete from auth.users where id = ?");
});

test("account deletion stops before destructive SQL when the profile is missing", async () => {
    const { database, queries } = createDatabaseStub({ profileExists: false });

    await assert.rejects(
        deleteAccount("user-id", database),
        /Account not found/,
    );

    assert.equal(
        queries.some((query) => query.startsWith("delete from public.fights")),
        false,
    );
    assert.equal(
        queries.some((query) => query.startsWith("delete from auth.users")),
        false,
    );
});

test("account deletion preserves the account and media references when Storage removal fails", async (t) => {
    const { database, queries } = createDatabaseStub({
        profileExists: true,
        mediaPaths: ["user-id/profile/avatar"],
    });
    const removal = t.mock.method(
        globalThis,
        "fetch",
        async () =>
            new Response(
                JSON.stringify({
                    message: "Storage unavailable",
                    statusCode: "503",
                }),
                {
                    status: 503,
                    headers: { "Content-Type": "application/json" },
                },
            ),
    );

    await assert.rejects(
        deleteAccount("user-id", database),
        /Could not remove uploaded photos/,
    );

    assert.equal(removal.mock.callCount(), 1);
    assert.equal(
        queries.some((query) => query.startsWith("delete from")),
        false,
    );
});

test("account deletion removes stored media before deleting its references and authentication", async (t) => {
    const { database, queries } = createDatabaseStub({
        profileExists: true,
        mediaPaths: ["user-id/profile/avatar", "user-id/fight_post/photo"],
    });
    let deletedRowsBeforeStorage = true;
    let removalBody = "";
    const removal = t.mock.method(
        globalThis,
        "fetch",
        async (...[, request]: Parameters<typeof fetch>) => {
            deletedRowsBeforeStorage = queries.some((query) =>
                query.startsWith("delete from"),
            );
            removalBody = String(request?.body);
            return new Response("[]", {
                status: 200,
                headers: { "Content-Type": "application/json" },
            });
        },
    );

    assert.equal(await deleteAccount("user-id", database), false);

    assert.equal(removal.mock.callCount(), 1);
    assert.equal(deletedRowsBeforeStorage, false);
    assert.deepEqual(JSON.parse(removalBody), {
        prefixes: ["user-id/profile/avatar", "user-id/fight_post/photo"],
    });
    assert.equal(queries.at(-1), "delete from auth.users where id = ?");
});
