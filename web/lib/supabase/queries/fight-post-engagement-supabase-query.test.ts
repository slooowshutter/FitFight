import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import type { Sql } from "postgres";
import { errorResponse } from "@/lib/http";
import {
    deleteFightPostCommentResponseSchema,
    fightPostCommentResponseSchema,
    fightPostReactionResponseSchema,
    fightPostReactionPeopleResponseSchema,
    listFightPostCommentsQuerySchema,
    listFightPostReactionPeopleQuerySchema,
    setFightPostReactionRequestSchema,
} from "@/lib/types/feed/fight-post";
import {
    createFightPostComment,
    deleteFightPostComment,
    listFightPostComments,
    listFightPostReactionPeople,
    setFightPostReaction,
} from "./fight-post-engagement-supabase-query";

const userId = "11111111-1111-4111-8111-111111111111";
const postId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

test("reaction people paginate independently of the unchanged reaction summary", async () => {
    const fixture = fightPostReactionPeopleResponseSchema.parse(
        JSON.parse(
            readFileSync(
                new URL(
                    "../../../../contracts/fixtures/post-reaction-people-response.json",
                    import.meta.url,
                ),
                "utf8",
            ),
        ),
    );
    const extraPerson = {
        ...fixture.people[0],
        user_id: "33333333-3333-4333-8333-333333333333",
    };
    let requestedCursor: string | undefined;
    const database = ((strings: TemplateStringsArray, ...values: unknown[]) => {
        const sql = strings.join("?").replace(/\s+/g, " ").trim();
        if (sql.includes("from public.fight_posts")) {
            return Promise.resolve([
                {
                    id: postId,
                    audience: "main",
                    fight_id: null,
                    author_id: userId,
                },
            ]);
        }
        assert.match(sql, /profile.deleted_at is null/);
        assert.match(
            sql,
            /blocked.blocked_id in \(reaction.user_id, \?::uuid\)/,
        );
        assert.match(sql, /order by reaction.user_id limit \?/);
        assert.deepEqual(values, [
            postId,
            requestedCursor ?? null,
            requestedCursor ?? null,
            userId,
            userId,
            3,
        ]);
        return Promise.resolve(
            requestedCursor ? [extraPerson] : [...fixture.people, extraPerson],
        );
    }) as unknown as Sql;
    const first = await listFightPostReactionPeople(
        userId,
        postId,
        { limit: 2 },
        database,
    );
    assert.deepEqual(first, fixture);
    assert.ok(first.next_cursor);
    requestedCursor = first.next_cursor;
    assert.deepEqual(
        await listFightPostReactionPeople(
            userId,
            postId,
            { limit: 2, cursor: requestedCursor },
            database,
        ),
        {
            people: [extraPerson],
            next_cursor: null,
        },
    );
});

test("reaction people are never queried without access to the post", async () => {
    for (const missing of [true, false]) {
        const database = ((strings: TemplateStringsArray) => {
            const sql = strings.join("?");
            if (sql.includes("from public.fight_posts")) {
                return Promise.resolve(
                    missing
                        ? []
                        : [
                              {
                                  id: postId,
                                  audience: "fight",
                                  fight_id: postId,
                                  author_id: userId,
                              },
                          ],
                );
            }
            assert.match(sql, /from public.fight_members as membership/);
            return Promise.resolve([]);
        }) as unknown as Sql;
        await assert.rejects(
            listFightPostReactionPeople(
                userId,
                postId,
                { limit: 40 },
                database,
            ),
            {
                status: missing ? 404 : 403,
            },
        );
    }
});

test("reaction people query validates cursors and bounded page sizes", () => {
    assert.deepEqual(listFightPostReactionPeopleQuerySchema.parse({}), {
        limit: 40,
    });
    assert.deepEqual(
        listFightPostReactionPeopleQuerySchema.parse({
            cursor: userId,
            limit: "2",
        }),
        { cursor: userId, limit: 2 },
    );
    for (const query of [
        { cursor: "invalid" },
        { limit: "0" },
        { limit: "81" },
        { limit: "1.5" },
    ]) {
        assert.equal(
            listFightPostReactionPeopleQuerySchema.safeParse(query).success,
            false,
        );
    }
});

test("a created comment returns the authoritative visible count after insertion and retains the legacy comment", async () => {
    const fixture = fightPostCommentResponseSchema.parse(
        JSON.parse(
            readFileSync(
                new URL(
                    "../../../../contracts/fixtures/post-comment-creation-response.json",
                    import.meta.url,
                ),
                "utf8",
            ),
        ),
    );
    const legacyFixture = JSON.parse(
        readFileSync(
            new URL(
                "../../../../contracts/fixtures/post-comment-creation-legacy-response.json",
                import.meta.url,
            ),
            "utf8",
        ),
    );
    assert.deepEqual(legacyFixture, { comment: fixture.comment });
    let inserted = false;
    const database = ((strings: TemplateStringsArray, ...values: unknown[]) => {
        const sql = strings.join("?").replace(/\s+/g, " ").trim();
        if (sql.includes("from public.fight_posts")) {
            return Promise.resolve([
                {
                    id: postId,
                    audience: "main",
                    fight_id: null,
                    author_id: userId,
                },
            ]);
        }
        if (sql.startsWith("select count(*)::int as n"))
            return Promise.resolve([{ n: 0 }]);
        if (sql.startsWith("insert into public.fight_post_comments")) {
            assert.deepEqual(values, [
                postId,
                null,
                userId,
                fixture.comment.body,
            ]);
            inserted = true;
            return Promise.resolve([{ id: fixture.comment.id }]);
        }
        if (sql.startsWith("select handle, display_name")) {
            return Promise.resolve([{ handle: "maya", display_name: "Maya" }]);
        }
        if (sql.startsWith("select comment.id")) {
            assert.equal(inserted, true);
            return Promise.resolve([
                {
                    ...fixture.comment,
                    author_id: userId,
                    author_handle: "maya",
                    author_display_name: "Maya",
                    author_companion_id: null,
                    avatar_id: null,
                },
            ]);
        }
        if (sql.startsWith("select count(*)::int as comment_count")) {
            assert.equal(
                inserted,
                true,
                "The count must include the newly saved comment",
            );
            assert.deepEqual(values, [postId, userId]);
            assert.match(
                sql,
                /private.feed_blocks as blocked where blocked.blocker_id = \? and blocked.blocked_id = comment.author_id/,
            );
            return Promise.resolve([{ comment_count: 3 }]);
        }
        throw new Error(`Unexpected query: ${sql}`);
    }) as unknown as Sql;

    const result = await createFightPostComment(
        userId,
        postId,
        { body: fixture.comment.body, tagged_user_ids: [] },
        database,
    );
    assert.deepEqual(result, fixture);
});

test("deleting a parent returns the remaining visible count after cascading replies", async () => {
    const fixture = deleteFightPostCommentResponseSchema.parse(
        JSON.parse(
            readFileSync(
                new URL(
                    "../../../../contracts/fixtures/post-comment-deletion-response.json",
                    import.meta.url,
                ),
                "utf8",
            ),
        ),
    );
    let deleted = false;
    const database = ((strings: TemplateStringsArray) => {
        const sql = strings.join("?");
        if (sql.includes("from public.fight_posts"))
            return Promise.resolve([
                {
                    id: postId,
                    audience: "main",
                    fight_id: null,
                    author_id: userId,
                },
            ]);
        if (sql.includes("delete from public.fight_post_comments")) {
            deleted = true;
            return Promise.resolve([{ id: postId }]);
        }
        assert.equal(deleted, true);
        assert.match(sql, /private.feed_blocks/);
        return Promise.resolve([{ comment_count: 2 }]);
    }) as unknown as Sql;
    assert.deepEqual(
        await deleteFightPostComment(userId, postId, postId, database),
        fixture,
    );
});

test("a saved reaction returns to the app without waiting for notification delivery", async () => {
    const requestFixture = setFightPostReactionRequestSchema.parse(
        JSON.parse(
            readFileSync(
                new URL(
                    "../../../../contracts/fixtures/post-reaction-request.json",
                    import.meta.url,
                ),
                "utf8",
            ),
        ),
    );
    const responseFixture = fightPostReactionResponseSchema.parse(
        JSON.parse(
            readFileSync(
                new URL(
                    "../../../../contracts/fixtures/post-reaction-response.json",
                    import.meta.url,
                ),
                "utf8",
            ),
        ),
    );
    let savedEmoji: string | null = null;
    let deliveryAttempted = false;
    const database = ((strings: TemplateStringsArray, ...values: unknown[]) => {
        const sql = strings.join("?").replace(/\s+/g, " ").trim();
        if (sql.includes("from public.fight_posts")) {
            return Promise.resolve([
                {
                    id: postId,
                    audience: "main",
                    fight_id: null,
                    author_id: userId,
                },
            ]);
        }
        if (sql.startsWith("select emoji")) {
            return Promise.resolve(
                savedEmoji === null ? [] : [{ emoji: savedEmoji }],
            );
        }
        if (sql.startsWith("insert into public.fight_post_reactions")) {
            assert.ok(typeof values[2] === "string");
            savedEmoji = values[2];
            return Promise.resolve([]);
        }
        if (sql.startsWith("delete from public.fight_post_reactions")) {
            savedEmoji = null;
            return Promise.resolve([]);
        }
        if (sql.includes("private.notification_intents")) {
            deliveryAttempted = true;
            return Promise.reject(new Error("Notification worker unavailable"));
        }
        if (sql.includes("from public.fight_post_reactions as reaction")) {
            return Promise.resolve(
                savedEmoji === null
                    ? []
                    : [
                          {
                              post_id: postId,
                              emoji: savedEmoji,
                              count: 1,
                              mine: true,
                          },
                      ],
            );
        }
        throw new Error(`Unexpected query: ${sql}`);
    }) as unknown as Sql;

    for (const emoji of [requestFixture.emoji, "\ud83d\udcaa", "\ud83d\ude02", "\u2764\ufe0f", "\ud83d\udc4f", "\ud83d\ude2e"]) {
        const response = await setFightPostReaction(
            userId,
            postId,
            emoji,
            database,
        ).then(
            (body) => new Response(JSON.stringify(body), { status: 200 }),
            errorResponse,
        );
        assert.equal(savedEmoji, emoji);
        assert.equal(
            response.status,
            200,
            "a persisted reaction must not become an Internal error",
        );
        assert.deepEqual(
            fightPostReactionResponseSchema.parse(await response.json()),
            emoji === requestFixture.emoji
                ? responseFixture
                : {
                      reactions: [{ emoji, count: 1, mine: true }],
                  },
        );
        assert.deepEqual(
            await setFightPostReaction(userId, postId, emoji, database),
            { reactions: [] },
        );
    }
    assert.equal(deliveryAttempted, false);
});

test("comment list query keeps omitted sort and accepts recent or comments", () => {
    assert.deepEqual(listFightPostCommentsQuerySchema.parse({}), {
        limit: 40,
    });
    assert.deepEqual(
        listFightPostCommentsQuerySchema.parse({ sort: "recent" }),
        { limit: 40, sort: "recent" },
    );
    assert.deepEqual(
        listFightPostCommentsQuerySchema.parse({ sort: "comments" }),
        { limit: 40, sort: "comments" },
    );
    assert.equal(
        listFightPostCommentsQuerySchema.safeParse({ sort: "likes" }).success,
        false,
    );
});

test("omitted comment sort still pages oldest first so installed clients stay compatible", async () => {
    const cursorId = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
    let seen = "";
    const database = ((strings: TemplateStringsArray, ...values: unknown[]) => {
        const sql = strings.join("?").replace(/\s+/g, " ").trim();
        if (sql.includes("from public.fight_posts")) {
            return Promise.resolve([
                {
                    id: postId,
                    audience: "main",
                    fight_id: null,
                    author_id: userId,
                },
            ]);
        }
        seen = sql;
        assert.match(sql, /order by comment.created_at, comment.id/);
        assert.doesNotMatch(sql, /created_at desc/);
        assert.deepEqual(values, [
            postId,
            userId,
            cursorId,
            postId,
            "2026-09-15T12:00:00Z",
            cursorId,
            41,
        ]);
        return Promise.resolve([]);
    }) as unknown as Sql;
    const result = await listFightPostComments(
        userId,
        postId,
        { limit: 40, cursor: `2026-09-15T12:00:00Z|${cursorId}` },
        database,
    );
    assert.match(seen, /\(comment.created_at, comment.id\) > /);
    assert.deepEqual(result, { comments: [], next_cursor: null });
});

test("recent comment sort pages newest first without changing the omitted contract", async () => {
    const cursorId = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
    let seen = "";
    const database = ((strings: TemplateStringsArray, ...values: unknown[]) => {
        const sql = strings.join("?").replace(/\s+/g, " ").trim();
        if (sql.includes("from public.fight_posts")) {
            return Promise.resolve([
                {
                    id: postId,
                    audience: "main",
                    fight_id: null,
                    author_id: userId,
                },
            ]);
        }
        seen = sql;
        assert.match(sql, /order by comment.created_at desc, comment.id desc/);
        assert.match(sql, /\(comment.created_at, comment.id\) < /);
        assert.deepEqual(values, [
            postId,
            userId,
            cursorId,
            postId,
            "2026-09-16T12:00:00Z",
            cursorId,
            41,
        ]);
        return Promise.resolve([]);
    }) as unknown as Sql;
    const result = await listFightPostComments(
        userId,
        postId,
        {
            limit: 40,
            sort: "recent",
            cursor: `2026-09-16T12:00:00Z|${cursorId}`,
        },
        database,
    );
    assert.match(seen, /\(comment.created_at, comment.id\) < /);
    assert.deepEqual(result, { comments: [], next_cursor: null });
});

test("most comments sort returns the busiest visible thread first", async () => {
    const busyId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    const quietId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
    const replyId = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
    const database = ((strings: TemplateStringsArray) => {
        const sql = strings.join("?");
        if (sql.includes("from public.fight_posts")) {
            return Promise.resolve([
                {
                    id: postId,
                    audience: "main",
                    fight_id: null,
                    author_id: userId,
                },
            ]);
        }
        return Promise.resolve([
            {
                id: busyId,
                post_id: postId,
                parent_id: null,
                body: "Busy",
                created_at: "2026-09-16T11:00:00Z",
                author_id: userId,
                author_handle: "maya",
                author_display_name: "Maya",
                author_companion_id: null,
                avatar_id: null,
            },
            {
                id: replyId,
                post_id: postId,
                parent_id: busyId,
                body: "Reply",
                created_at: "2026-09-16T11:30:00Z",
                author_id: userId,
                author_handle: "maya",
                author_display_name: "Maya",
                author_companion_id: null,
                avatar_id: null,
            },
            {
                id: quietId,
                post_id: postId,
                parent_id: null,
                body: "Quiet",
                created_at: "2026-09-16T12:00:00Z",
                author_id: userId,
                author_handle: "maya",
                author_display_name: "Maya",
                author_companion_id: null,
                avatar_id: null,
            },
        ]);
    }) as unknown as Sql;
    const first = await listFightPostComments(
        userId,
        postId,
        { limit: 1, sort: "comments" },
        database,
    );
    assert.deepEqual(
        first.comments.map((comment) => comment.id),
        [busyId, replyId],
    );
    assert.equal(
        first.next_cursor,
        `1|2026-09-16T11:00:00.000Z|${busyId}`,
    );
    const second = await listFightPostComments(
        userId,
        postId,
        { limit: 1, sort: "comments", cursor: first.next_cursor ?? undefined },
        database,
    );
    assert.deepEqual(
        second.comments.map((comment) => comment.id),
        [quietId],
    );
    assert.equal(second.next_cursor, null);
});
