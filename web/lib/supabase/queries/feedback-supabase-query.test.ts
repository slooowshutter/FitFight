import assert from "node:assert/strict";
import { test } from "node:test";
import type { Sql } from "postgres";
import { createClient } from "@supabase/supabase-js";
import { DELETE as deleteFeedbackRoute } from "@/app/api/v1/feedback/[postID]/route";
import { ApiError } from "@/lib/http";
import {
    blockFeedbackAuthorRequestSchema,
    createFeedbackCommentRequestSchema,
    createFeedbackPostRequestSchema,
    feedbackDetailResponseSchema,
    feedbackListResponseSchema,
    launchFeedbackFixRequestSchema,
    listFeedbackQuerySchema,
    reportFeedbackPostRequestSchema,
} from "@/lib/types/feedback/feedback";
import {
    blockFeedbackAuthor,
    createFeedbackComment,
    createFeedbackPost,
    deleteFeedbackPost,
    listFeedbackPosts,
    reportFeedbackPost,
    toggleFeedbackVote,
} from "./feedback-supabase-query";

const userId = "11111111-1111-4111-8111-111111111111";
const authorId = "22222222-2222-4222-8222-222222222222";
const postId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";

const postRow = {
    id: postId,
    kind: "bug" as const,
    title: "Steps chart is blank",
    body: "The daily Steps chart on a live fight stays empty after a successful sync.",
    vote_count: 3,
    comment_count: 1,
    voted: true,
    author_id: authorId,
    author_handle: "maya_moves",
    mine: false,
    created_at: new Date("2026-09-04T12:00:00.000Z"),
    metadata: {
        app_version: "1.0.0",
        app_build: "183",
        os: "iOS",
        os_version: "26.0",
        language: "fr",
    },
};

test("feedback deletion authenticates before accessing the database", async () => {
    const response = await deleteFeedbackRoute(
        new Request(`https://staging.fitfight.app/api/v1/feedback/${postId}`, {
            method: "DELETE",
        }),
        { params: Promise.resolve({ postID: postId }) },
    );
    assert.equal(response.status, 401);
});

test("only the author or a trusted admin account can delete feedback", async (t) => {
    for (const scenario of [
        {
            name: "Marc's handle with an Apple relay email",
            handle: "marc",
            email: "relay@privaterelay.appleid.com",
            confirmed: true,
            status: 200,
        },
        {
            name: "case-insensitive admin handle",
            handle: "MARC",
            email: "relay@privaterelay.appleid.com",
            confirmed: true,
            status: 200,
        },
        {
            name: "confirmed admin email",
            handle: "owner",
            email: "marc@marclamy.com",
            confirmed: true,
            status: 200,
        },
        {
            name: "post author",
            handle: "maya_moves",
            email: "maya@example.com",
            confirmed: true,
            owns: true,
            status: 200,
        },
        {
            name: "regular account",
            handle: "maya_moves",
            email: "maya@example.com",
            confirmed: true,
            status: 403,
        },
        {
            name: "spoofed user metadata email",
            handle: "maya_moves",
            email: "maya@example.com",
            confirmed: true,
            spoofed: true,
            status: 403,
        },
        {
            name: "unconfirmed admin email",
            handle: "maya_moves",
            email: "marc@marclamy.com",
            confirmed: false,
            status: 403,
        },
        {
            name: "deleted account",
            handle: null,
            email: "marc@marclamy.com",
            confirmed: true,
            status: 401,
        },
        {
            name: "already deleted request",
            handle: "marc",
            email: "relay@privaterelay.appleid.com",
            confirmed: true,
            missing: true,
            status: 404,
        },
    ]) {
        await t.test(scenario.name, async () => {
            const admin = createClient("https://feedback.example", "test-only-key", {
                auth: { persistSession: false, autoRefreshToken: false },
                global: {
                    fetch: async (input, init) => {
                        const url = new URL(new Request(input, init).url);
                        if (url.pathname === "/rest/v1/profiles") {
                            assert.equal(url.searchParams.get("id"), `eq.${userId}`);
                            assert.equal(url.searchParams.get("deleted_at"), "is.null");
                            return Response.json(scenario.handle ? [{ handle: scenario.handle }] : []);
                        }
                        assert.equal(url.pathname, `/auth/v1/admin/users/${userId}`);
                        return Response.json({
                            id: userId,
                            email: scenario.email,
                            email_confirmed_at: scenario.confirmed ? "2026-09-01T00:00:00Z" : null,
                            user_metadata: scenario.spoofed ? { email: "marc@marclamy.com" } : {},
                            identities: [],
                            app_metadata: {},
                            aud: "authenticated",
                            created_at: "2026-09-01T00:00:00Z",
                        });
                    },
                },
            });
            const { database, queries, bound } = createDatabaseStub(() => scenario.missing ? [] : [{ author_id: scenario.owns ? userId : authorId }]);
            if (scenario.status === 200) {
                await deleteFeedbackPost(userId, postId, admin, database);
            } else {
                await assert.rejects(
                    deleteFeedbackPost(userId, postId, admin, database),
                    (error: unknown) => error instanceof ApiError && error.status === scenario.status,
                );
            }
            if (scenario.status === 200 || scenario.status === 404) {
                assert.match(queries[0], /select author_id .* for update/);
                if (scenario.status === 200) assert.match(queries[1], /delete from public.feedback_posts/);
                assert.deepEqual(bound, scenario.status === 200 ? [[postId], [postId]] : [[postId]]);
            } else if (scenario.status === 401) {
                assert.deepEqual(queries, []);
            } else {
                assert.equal(queries.length, 1);
                assert.match(queries[0], /select author_id/);
            }
        });
    }
});

test("feedback detail keeps legacy responses readable and deletion opt-in", () => {
    const legacyDetail = {
        post: { ...postRow, created_at: "2026-09-04T12:00:00Z", media: [] },
        comments: [],
        can_launch_fix: true,
    };
    assert.equal(feedbackDetailResponseSchema.parse(legacyDetail).can_delete, false);
    assert.equal(feedbackDetailResponseSchema.parse({ ...legacyDetail, can_delete: true }).can_delete, true);
    assert.equal(feedbackDetailResponseSchema.parse({ ...legacyDetail, can_delete: false }).can_delete, false);
});

function createDatabaseStub(respond: (query: string) => unknown[]) {
    const queries: string[] = [];
    const bound: unknown[][] = [];
    const query = ((first: TemplateStringsArray, ...values: unknown[]) => {
        if (!("raw" in first)) {
            return first;
        }
        const sql = first.join("?").replace(/\s+/g, " ").trim();
        queries.push(sql);
        bound.push(values);
        return Promise.resolve(respond(sql));
    }) as unknown as Sql;
    const database = Object.assign(query, {
        begin: async (
            _options: string,
            callback: (sql: Sql) => Promise<unknown>,
        ) => callback(query),
        json: (value: unknown) => value,
    });
    return { database, queries, bound };
}

test("feedback schemas accept a one-character title and details", () => {
    const created = createFeedbackPostRequestSchema.parse({
        kind: "feature",
        title: "H",
        body: "A",
    });
    assert.equal(created.kind, "feature");
    assert.equal(created.title, "H");
    assert.equal(created.body, "A");
    assert.deepEqual(created.media_ids, []);
    assert.throws(() =>
        createFeedbackPostRequestSchema.parse({
            kind: "feature",
            title: " ",
            body: "A weekly Steps total on You would make it easier to plan a fight.",
        }),
    );
    assert.throws(() =>
        createFeedbackPostRequestSchema.parse({
            kind: "feature",
            title: "Show weekly totals",
            body: " ",
        }),
    );
    assert.throws(() =>
        createFeedbackPostRequestSchema.parse({
            kind: "idea",
            title: "Show weekly totals",
            body: "A weekly Steps total on You would make it easier to plan a fight.",
        }),
    );
    assert.throws(() =>
        createFeedbackCommentRequestSchema.parse({ body: "x" }),
    );
    assert.deepEqual(
        createFeedbackPostRequestSchema.parse({
            kind: "bug",
            title: "H",
            body: "A",
            metadata: {
                app_version: "1.0.0",
                app_build: "183",
                language: "fr",
                os: "iOS",
                os_version: "26.0",
                extra_flag: true,
            },
        }).metadata,
        {
            app_version: "1.0.0",
            app_build: "183",
            language: "fr",
            os: "iOS",
            os_version: "26.0",
            extra_flag: true,
        },
    );
    assert.throws(() =>
        createFeedbackPostRequestSchema.parse({
            kind: "bug",
            title: "H",
            body: "A",
            metadata: { app_version: "x".repeat(9000) },
        }),
    );
    assert.deepEqual(listFeedbackQuerySchema.parse({}), {});
    assert.deepEqual(listFeedbackQuerySchema.parse({}), {});
    assert.equal(listFeedbackQuerySchema.parse({ kind: "bug" }).kind, "bug");
    assert.equal(
        feedbackDetailResponseSchema.parse({
            post: {
                id: postId,
                kind: "bug",
                title: postRow.title,
                body: postRow.body,
                vote_count: 3,
                comment_count: 1,
                voted: true,
                author_id: authorId,
                author_handle: "maya_moves",
                mine: false,
                created_at: "2026-09-04T12:00:00Z",
                metadata: postRow.metadata,
                media: [],
            },
            comments: [],
            can_launch_fix: true,
        }).can_launch_fix,
        true,
    );
    assert.equal(
        reportFeedbackPostRequestSchema.safeParse({ reason: "other" }).success,
        true,
    );
    assert.equal(
        blockFeedbackAuthorRequestSchema.safeParse({ user_id: authorId })
            .success,
        true,
    );
    assert.deepEqual(launchFeedbackFixRequestSchema.parse({}), {});
    assert.deepEqual(
        launchFeedbackFixRequestSchema.parse({
            metadata: { app_version: "1.0.0", device_model: "iPhone18,1" },
        }).metadata,
        { app_version: "1.0.0", device_model: "iPhone18,1" },
    );
    assert.throws(() => launchFeedbackFixRequestSchema.parse({ extra: true }));
    assert.throws(() => createFeedbackPostRequestSchema.parse({ extra: true }));
    assert.equal(
        createFeedbackPostRequestSchema.safeParse({
            kind: "bug",
            title: "H",
            body: "A",
            media_ids: ["not-a-uuid"],
        }).success,
        false,
    );
    assert.equal(
        createFeedbackPostRequestSchema.safeParse({
            kind: "bug",
            title: "H",
            body: "A",
            media_ids: Array.from({ length: 9 }, () => postId),
        }).success,
        false,
    );
    assert.deepEqual(
        createFeedbackPostRequestSchema.parse({
            kind: "bug",
            title: "H",
            body: "A",
            media_ids: [postId],
        }).media_ids,
        [postId],
    );
    assert.deepEqual(
        createFeedbackPostRequestSchema.parse({
            kind: "bug",
            title: "H",
            body: "A",
            metadata: {
                os: "iOS",
                look: "night",
                idiom: "phone",
                locale: "fr_FR",
                region: "FR",
                backend: "staging",
                calendar: "gregorian",
                language: "fr",
                app_build: "190",
                bold_text: false,
                bundle_id: "com.fitfight.mvp",
                time_zone: "Europe/Paris",
                appearance: "dark",
                hour_cycle: "24",
                os_version: "26.6.1",
                voice_over: false,
                app_version: "1.0.0",
                content_size: "UICTContentSizeCategoryL",
                device_model: "iPhone14,5",
                screen_scale: 3,
                screen_width: 390,
                reduce_motion: false,
                screen_height: 844,
                thermal_state: "fair",
                low_power_mode: false,
                layout_direction: "ltr",
                increase_contrast: false,
                background_refresh: "available",
                measurement_system: "metric",
                preferred_languages: ["fr-FR"],
            },
        }).metadata?.device_model,
        "iPhone14,5",
    );
});

test("listing feedback posts maps vote counts and the viewer vote", async () => {
    const { database, queries } = createDatabaseStub((sql) => {
        if (sql.includes("feedback_post_media")) {
            return [];
        }
        return [postRow];
    });

    const result = await listFeedbackPosts(userId, { kind: "bug" }, database);

    assert.match(queries[0] ?? "", /from public.feedback_posts as post/);
    assert.match(queries[0] ?? "", /private.feedback_blocks/);
    assert.ok(queries.some((query) => query.includes("feedback_post_media")));
    assert.deepEqual(feedbackListResponseSchema.parse(result), {
        posts: [
            {
                id: postId,
                kind: "bug",
                title: postRow.title,
                body: postRow.body,
                vote_count: 3,
                comment_count: 1,
                voted: true,
                author_id: authorId,
                author_handle: "maya_moves",
                mine: false,
                created_at: "2026-09-04T12:00:00Z",
                metadata: postRow.metadata,
                media: [],
                archived: false,
                archive_reason: null,
            },
        ],
    });
});

test("creating a feedback post is refused after the daily cap", async () => {
    const { database, queries } = createDatabaseStub((sql) => {
        if (sql.includes("interval '24 hours'")) {
            return [{ n: 8 }];
        }
        return [postRow];
    });

    await assert.rejects(
        () =>
            createFeedbackPost(
                userId,
                {
                    kind: "bug",
                    title: postRow.title,
                    body: postRow.body,
                    media_ids: [],
                },
                database,
            ),
        (error: unknown) =>
            error instanceof ApiError && error.code === "rate_limited",
    );
    assert.equal(
        queries.some((query) =>
            query.includes("insert into public.feedback_posts"),
        ),
        false,
    );
});

test("creating a feedback post inserts the trimmed write-up", async () => {
    const { database, queries, bound } = createDatabaseStub((sql) => {
        if (sql.includes("interval '24 hours'")) {
            return [{ n: 1 }];
        }
        return [{ ...postRow, vote_count: 0, comment_count: 0, voted: false }];
    });

    const result = await createFeedbackPost(
        userId,
        {
            kind: "bug",
            title: postRow.title,
            body: postRow.body,
            media_ids: [],
            metadata: {
                app_version: "1.0.0",
                os: "iOS",
            },
        },
        database,
    );

    assert.ok(
        queries.some((query) =>
            query.includes("insert into public.feedback_posts"),
        ),
    );
    assert.ok(queries.some((query) => query.includes("metadata")));
    assert.deepEqual(
        bound
            .flat()
            .find(
                (value) =>
                    typeof value === "object" &&
                    value !== null &&
                    "app_version" in value,
            ),
        { app_version: "1.0.0", os: "iOS" },
    );
    assert.equal(
        bound
            .flat()
            .some(
                (value) => typeof value === "string" && value.startsWith("{"),
            ),
        false,
    );
    assert.equal(result.post.vote_count, 0);
    assert.equal(result.post.voted, false);
    assert.equal(result.post.author_handle, "maya_moves");
    assert.deepEqual(result.post.media, []);
    assert.deepEqual(result.post.metadata, postRow.metadata);
});

test("toggling a vote inserts when the viewer has not voted", async () => {
    const { database, queries } = createDatabaseStub((sql) => {
        if (sql.includes("select archived, archive_reason from public.feedback_posts")) {
            return [{ archived: false, archive_reason: null }];
        }
        if (sql.includes("delete from public.feedback_votes")) {
            return [];
        }
        if (sql.includes("insert into public.feedback_votes")) {
            return [];
        }
        return [{ vote_count: 1 }];
    });

    const result = await toggleFeedbackVote(userId, postId, database);

    assert.equal(result.voted, true);
    assert.equal(result.vote_count, 1);
    assert.ok(
        queries.some((query) =>
            query.includes("insert into public.feedback_votes"),
        ),
    );
    assert.ok(
        queries.some((query) =>
            query.includes("on conflict (post_id, user_id) do nothing"),
        ),
    );
});

test("reporting a feedback post records the reason", async () => {
    const { database, queries } = createDatabaseStub((sql) => {
        if (sql.includes("from public.feedback_posts as post")) {
            return [{ id: postId, author_id: authorId }];
        }
        return [];
    });

    const result = await reportFeedbackPost(
        userId,
        postId,
        { reason: "other" },
        database,
    );

    assert.deepEqual(result, { reported: true });
    assert.ok(
        queries.some((query) =>
            query.includes("insert into private.feedback_post_reports"),
        ),
    );
});

test("blocking a feedback author hides them from the viewer", async () => {
    const { database, queries } = createDatabaseStub((sql) => {
        if (sql.includes("select id as user_id from public.profiles")) {
            return [{ user_id: authorId }];
        }
        return [];
    });

    const result = await blockFeedbackAuthor(userId, authorId, database);

    assert.deepEqual(result, { blocked: true });
    assert.ok(
        queries.some((query) =>
            query.includes("insert into private.feedback_blocks"),
        ),
    );
});

test("commenting on a missing post returns not found", async () => {
    const { database } = createDatabaseStub((sql) => {
        if (sql.includes("interval '24 hours'")) {
            return [{ n: 0 }];
        }
        return [];
    });

    await assert.rejects(
        () =>
            createFeedbackComment(
                userId,
                postId,
                { body: "I see this too." },
                database,
            ),
        (error: unknown) =>
            error instanceof ApiError && error.code === "not_found",
    );
});

test("creating a feedback comment stores client metadata", async () => {
    const { database, queries, bound } = createDatabaseStub((sql) => {
        if (sql.includes("select archived, archive_reason")) return [{ archived: false, archive_reason: null }];
        if (sql.includes("interval '24 hours'")) {
            return [{ n: 0 }];
        }
        return [
            {
                id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
                body: "I see this too.",
                author_handle: "maya_moves",
                created_at: new Date("2026-09-04T13:00:00.000Z"),
                metadata: { app_version: "1.0.0", os: "iOS" },
            },
        ];
    });

    const result = await createFeedbackComment(
        userId,
        postId,
        {
            body: "I see this too.",
            metadata: { app_version: "1.0.0", os: "iOS" },
        },
        database,
    );

    assert.ok(
        queries.some((query) =>
            query.includes("insert into public.feedback_comments"),
        ),
    );
    assert.ok(queries.some((query) => query.includes("metadata")));
    assert.deepEqual(
        bound
            .flat()
            .find(
                (value) =>
                    typeof value === "object" &&
                    value !== null &&
                    "app_version" in value,
            ),
        { app_version: "1.0.0", os: "iOS" },
    );
    assert.equal(
        bound
            .flat()
            .some(
                (value) => typeof value === "string" && value.startsWith("{"),
            ),
        false,
    );
    assert.deepEqual(result.comment.metadata, {
        app_version: "1.0.0",
        os: "iOS",
    });
});


test("archived feedback rejects votes and comments without changing either", async () => {
    const { database, queries } = createDatabaseStub((sql) => {
        if (sql.includes("interval '24 hours'")) return [{ n: 0 }];
        return [{ archived: true, archive_reason: "Resolved" }];
    });
    for (const action of [
        () => toggleFeedbackVote(userId, postId, database),
        () => createFeedbackComment(userId, postId, { body: "Me too" }, database),
    ]) {
        await assert.rejects(action, (error: unknown) => error instanceof ApiError && error.status === 409);
    }
    assert.equal(queries.some((query) => /insert into|delete from/.test(query)), false);
});

test("feedback filters validate type, status, and sort independently", () => {
    assert.deepEqual(listFeedbackQuerySchema.parse({}), {});
    assert.deepEqual(listFeedbackQuerySchema.parse({ status: "archived", kind: "bug", sort: "oldest" }), {
        status: "archived", kind: "bug", sort: "oldest",
    });
    for (const input of [{ status: "hidden" }, { sort: "random" }, { kind: "all" }]) {
        assert.equal(listFeedbackQuerySchema.safeParse(input).success, false);
    }
});
