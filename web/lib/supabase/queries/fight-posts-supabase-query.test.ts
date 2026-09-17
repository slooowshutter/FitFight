import assert from "node:assert/strict";
import { test } from "node:test";
import { GET as listFeed } from "@/app/api/v1/feed/route";
import { POST as blockAuthor } from "@/app/api/v1/feed/blocks/route";
import { GET as listPeople } from "@/app/api/v1/feed/people/route";
import { POST as createFeedPosts } from "@/app/api/v1/feed/posts/route";
import {
    GET as listPosts,
    POST as createPost,
} from "@/app/api/v1/fights/[fightID]/posts/route";
import { DELETE as deletePost } from "@/app/api/v1/fights/[fightID]/posts/[postID]/route";
import { POST as reportPost } from "@/app/api/v1/fights/[fightID]/posts/[postID]/report/route";
import {
    GET as listComments,
    POST as createComment,
} from "@/app/api/v1/posts/[postID]/comments/route";
import { PATCH as updatePost } from "@/app/api/v1/posts/[postID]/route";
import { POST as reactToPost } from "@/app/api/v1/posts/[postID]/reactions/route";
import {
    createFeedPostsRequestSchema,
    createFightPostCommentRequestSchema,
    createFightPostRequestSchema,
    fightPostAuthorSchema,
    listFightPostsQuerySchema,
    reportFightPostRequestSchema,
    setFightPostReactionRequestSchema,
    updateFightPostRequestSchema,
} from "@/lib/types/feed/fight-post";
import {
    createFeedPosts as writeFeedPosts,
    listFeedPeople,
    listFightPosts,
    loadVisiblePost,
} from "./fight-posts-supabase-query";
import type { Sql } from "postgres";

const userId = "11111111-1111-4111-8111-111111111111";
const fightId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const postId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

test("fight posts need a note or a photo and reject extra fields", () => {
    assert.deepEqual(
        createFightPostRequestSchema.parse({ body: "Made it up the hill." }),
        {
            body: "Made it up the hill.",
            media_ids: [],
        },
    );
    assert.equal(createFightPostRequestSchema.safeParse({}).success, false);
    assert.equal(
        createFightPostRequestSchema.safeParse({ body: "", media_ids: [] })
            .success,
        false,
    );
    assert.equal(
        createFightPostRequestSchema.safeParse({
            body: "x",
            media_ids: ["not-a-uuid"],
        }).success,
        false,
    );
    assert.equal(
        createFightPostRequestSchema.safeParse({
            body: "x",
            fight_id: fightId,
        }).success,
        false,
    );
    assert.equal(
        reportFightPostRequestSchema.safeParse({ reason: "nope" }).success,
        false,
    );
    assert.deepEqual(listFightPostsQuerySchema.parse({}), { limit: 30 });
    assert.deepEqual(listFightPostsQuerySchema.parse({ scope: "all" }), {
        limit: 30,
        scope: "all",
    });
    assert.deepEqual(
        createFeedPostsRequestSchema.parse({
            body: "Hill.",
            destinations: [
                { type: "main" },
                { type: "fight", fight_id: fightId },
            ],
        }),
        {
            body: "Hill.",
            media_ids: [],
            destinations: [
                { type: "main" },
                { type: "fight", fight_id: fightId },
            ],
            tagged_user_ids: [],
        },
    );
    assert.deepEqual(
        createFeedPostsRequestSchema.parse({
            body: "Hill.",
            destinations: [{ type: "fight", fight_id: fightId }],
        }),
        {
            body: "Hill.",
            media_ids: [],
            destinations: [{ type: "fight", fight_id: fightId }],
            tagged_user_ids: [],
        },
    );
    assert.equal(
        createFeedPostsRequestSchema.safeParse({
            body: "Hill.",
            destinations: Array.from({ length: 9 }, () => ({
                type: "fight" as const,
                fight_id: fightId,
            })),
        }).success,
        true,
    );
    assert.equal(
        createFeedPostsRequestSchema.safeParse({
            body: "Hill.",
            destinations: [],
        }).success,
        false,
    );
    assert.deepEqual(
        createFeedPostsRequestSchema.parse({
            body: "Hello everyone.",
            destinations: [{ type: "broadcast" }],
        }),
        {
            body: "Hello everyone.",
            media_ids: [],
            destinations: [{ type: "broadcast" }],
            tagged_user_ids: [],
        },
    );
    assert.equal(
        createFeedPostsRequestSchema.safeParse({
            body: "Hello everyone.",
            destinations: [{ type: "broadcast" }, { type: "main" }],
        }).success,
        false,
    );
    assert.equal(
        createFightPostCommentRequestSchema.safeParse({ body: "" }).success,
        false,
    );
    assert.deepEqual(
        createFightPostCommentRequestSchema.parse({ body: "See you on the walk!" }),
        { body: "See you on the walk!", tagged_user_ids: [] },
    );
    assert.equal(
        setFightPostReactionRequestSchema.safeParse({ emoji: "abc" }).success,
        false,
    );
    assert.equal(
        setFightPostReactionRequestSchema.safeParse({ emoji: "\ud83d\udd25" }).success,
        true,
    );
    assert.deepEqual(
        updateFightPostRequestSchema.parse({ body: "  edited  " }),
        { body: "edited" },
    );
    assert.equal(
        updateFightPostRequestSchema.safeParse({ body: "x".repeat(501) })
            .success,
        false,
    );
    assert.equal(
        updateFightPostRequestSchema.safeParse({ body: "", media_ids: [] })
            .success,
        false,
    );
});
