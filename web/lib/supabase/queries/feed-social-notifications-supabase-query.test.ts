import assert from "node:assert/strict";
import test from "node:test";
import { z } from "zod";
import { socialNotificationAlert } from "@/lib/notifications/notification-copy";
import { GET, PATCH } from "@/app/api/v1/notifications/preferences/route";
import {
    eligibleMentionUserIds,
    enqueueFightFeedCommentNotifications,
    enqueueFightFeedPostNotifications,
    enqueueFightFeedReactionNotifications,
    enqueueMentionNotifications,
    mentionHandlesFromBody,
} from "./feed-social-notifications-supabase-query";
import {
    defaultNotificationPreferences,
    updateNotificationPreferencesRequestSchema,
} from "@/lib/types/notifications/notification-preferences";
import type { Sql } from "postgres";

const actorId = "11111111-1111-4111-8111-111111111111";
const otherId = "22222222-2222-4222-8222-222222222222";
const thirdId = "33333333-3333-4333-8333-333333333333";
const fightId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const siblingFightId = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";
const postId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const commentId = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const parentId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";

test("comment alerts identify the exact post and comment", async () => {
    const { database, inserted } = createSql({
        post: { fight_id: fightId, author_id: otherId },
        members: [{ user_id: otherId, fight_id: fightId }],
        actor: { handle: "alex", display_name: "Alex" },
        recipients: [{
            user_id: otherId, locale: "en", feed_post: true,
            post_comment: true, comment_reply: true, post_reaction: true,
        }],
    });
    await enqueueFightFeedCommentNotifications(database, {
        postId, commentId, parentId: null, actorId,
    });
    const row = z.object({ route: z.string() }).parse(inserted[0]);
    const target = new URL(row.route, "https://fitfight.app");
    assert.equal(target.pathname, `/fights/${fightId}`);
    assert.equal(target.searchParams.get("post"), postId);
    assert.equal(target.searchParams.get("comment"), commentId);
});

function createSql(options: {
    members?: Array<{ user_id: string; fight_id: string }>;
    actor?: { handle: string; display_name: string };
    recipients?: Array<{
        user_id: string;
        locale: string | null;
        feed_post: boolean | null;
        post_comment: boolean | null;
        comment_reply: boolean | null;
        post_reaction: boolean | null;
    }>;
    post?: { fight_id: string | null; author_id: string };
    parent?: { author_id: string };
}) {
    const queries: string[] = [];
    const inserted: unknown[] = [];
    const query = ((first: unknown, ...values: unknown[]) => {
        if (
            Array.isArray(first) &&
            !Object.prototype.hasOwnProperty.call(first, "raw")
        ) {
            return first;
        }
        const strings = first as TemplateStringsArray;
        const sql = strings.join("?").replace(/\s+/g, " ").trim();
        queries.push(sql);
        for (const value of values) {
            if (
                Array.isArray(value) &&
                value[0] !== undefined &&
                typeof value[0] === "object" &&
                value[0] !== null &&
                "idempotency_key" in value[0]
            ) {
                inserted.push(...value);
            }
        }
        if (sql.includes("from public.fight_members")) {
            return Promise.resolve(options.members ?? []);
        }
        if (sql.includes("from public.fight_posts")) {
            return Promise.resolve(options.post ? [options.post] : []);
        }
        if (sql.includes("from public.fight_post_comments")) {
            return Promise.resolve(options.parent ? [options.parent] : []);
        }
        if (sql.includes("from public.profiles as profile")) {
            return Promise.resolve(options.recipients ?? []);
        }
        if (sql.includes("from public.profiles")) {
            return Promise.resolve(options.actor ? [options.actor] : []);
        }
        return Promise.resolve([]);
    }) as unknown as Sql;
    Object.assign(query, {
        json: (value: unknown) => value,
    });
    return { database: query, queries, inserted };
}

test("mention handles come from @tags and ignore emails", () => {
    assert.deepEqual(mentionHandlesFromBody("hey @Marc and @maya_moves!"), [
        "marc",
        "maya_moves",
    ]);
    assert.deepEqual(mentionHandlesFromBody("write marc@marclamy.com"), []);
    assert.deepEqual(mentionHandlesFromBody("@x @ok"), ["ok"]);
    assert.deepEqual(mentionHandlesFromBody("@marc @Marc"), ["marc"]);
});

test("social alert copy names the person and stays off health numbers", () => {
    const alert = socialNotificationAlert("feed_post", "Alex", "en");
    assert.equal(alert.title, "FitFight");
    assert.equal(alert.body, "Alex posted in the feed.");
    assert.doesNotMatch(alert.body, /step/i);
    assert.doesNotMatch(alert.body, /score/i);
    assert.equal(
        socialNotificationAlert("comment_reply", "Alex", "fr").body,
        "Alex a répondu à ton commentaire.",
    );
});

test("notification preference patches need at least one toggle", () => {
    assert.deepEqual(
        updateNotificationPreferencesRequestSchema.parse({ feed_post: false }),
        { feed_post: false },
    );
    assert.equal(
        updateNotificationPreferencesRequestSchema.safeParse({}).success,
        false,
    );
    assert.equal(defaultNotificationPreferences.comment_reply, true);
});

test("notification preference routes authenticate before reading or writing", async () => {
    const context = { params: Promise.resolve({}) };
    const get = await GET(
        new Request(
            "https://staging.fitfight.app/api/v1/notifications/preferences",
        ),
        context,
    );
    const patch = await PATCH(
        new Request(
            "https://staging.fitfight.app/api/v1/notifications/preferences",
            {
                method: "PATCH",
            },
        ),
        context,
    );
    assert.equal(get.status, 401);
    assert.equal(patch.status, 401);
});

test("a fight post notifies other members and skips the author", async () => {
    const { database, inserted } = createSql({
        members: [
            { user_id: otherId, fight_id: fightId },
            { user_id: actorId, fight_id: fightId },
        ],
        actor: { handle: "alex", display_name: "Alex" },
        recipients: [
            {
                user_id: otherId,
                locale: "en",
                feed_post: true,
                post_comment: true,
                comment_reply: true,
                post_reaction: true,
            },
        ],
    });
    await enqueueFightFeedPostNotifications(database, {
        fightId,
        postId,
        actorId,
    });
    assert.equal(inserted.length, 1);
    const row = inserted[0] as {
        user_id: string;
        kind: string;
        alert_body: string;
        fight_id: string;
        route: string;
    };
    assert.equal(row.user_id, otherId);
    assert.equal(row.kind, "feed_post");
    assert.equal(row.alert_body, "Alex posted in the feed.");
    assert.equal(row.fight_id, fightId);
    assert.equal(row.route, `/fights/${fightId}?post=${postId}`);
});

test("a series-sibling member is routed to their own fight", async () => {
    const { database, inserted, queries } = createSql({
        members: [{ user_id: otherId, fight_id: siblingFightId }],
        actor: { handle: "alex", display_name: "Alex" },
        recipients: [
            {
                user_id: otherId,
                locale: "en",
                feed_post: true,
                post_comment: true,
                comment_reply: true,
                post_reaction: true,
            },
        ],
    });
    await enqueueFightFeedPostNotifications(database, {
        fightId,
        postId,
        actorId,
    });
    assert.equal(inserted.length, 1);
    const row = inserted[0] as { fight_id: string; route: string };
    assert.equal(row.fight_id, siblingFightId);
    assert.equal(new URL(row.route, "https://fitfight.app").pathname, `/fights/${siblingFightId}`);
    assert.equal(new URL(row.route, "https://fitfight.app").searchParams.get("post"), postId);
    assert.ok(queries.some((sql) => sql.includes("series_id")));
});

test("a muted feed-post preference is not enqueued", async () => {
    const { database, inserted } = createSql({
        members: [{ user_id: otherId, fight_id: fightId }],
        actor: { handle: "alex", display_name: "Alex" },
        recipients: [
            {
                user_id: otherId,
                locale: "en",
                feed_post: false,
                post_comment: true,
                comment_reply: true,
                post_reaction: true,
            },
        ],
    });
    await enqueueFightFeedPostNotifications(database, {
        fightId,
        postId,
        actorId,
    });
    assert.equal(inserted.length, 0);
});

test("a top-level comment notifies the post author only", async () => {
    const { database, inserted } = createSql({
        post: { fight_id: fightId, author_id: otherId },
        members: [{ user_id: otherId, fight_id: fightId }],
        actor: { handle: "alex", display_name: "Alex" },
        recipients: [
            {
                user_id: otherId,
                locale: "en",
                feed_post: true,
                post_comment: true,
                comment_reply: true,
                post_reaction: true,
            },
        ],
    });
    await enqueueFightFeedCommentNotifications(database, {
        postId,
        commentId,
        parentId: null,
        actorId,
    });
    assert.equal(inserted.length, 1);
    assert.equal((inserted[0] as { kind: string }).kind, "post_comment");
    assert.equal((inserted[0] as { user_id: string }).user_id, otherId);
});

test("a reply to the post author’s comment is one reply, not also a comment", async () => {
    const { database, inserted } = createSql({
        post: { fight_id: fightId, author_id: otherId },
        parent: { author_id: otherId },
        members: [{ user_id: otherId, fight_id: fightId }],
        actor: { handle: "alex", display_name: "Alex" },
        recipients: [
            {
                user_id: otherId,
                locale: "en",
                feed_post: true,
                post_comment: true,
                comment_reply: true,
                post_reaction: true,
            },
        ],
    });
    await enqueueFightFeedCommentNotifications(database, {
        postId,
        commentId,
        parentId,
        actorId,
    });
    assert.equal(inserted.length, 1);
    assert.equal(
        (inserted[0] as { kind: string; user_id: string }).kind,
        "comment_reply",
    );
    assert.equal((inserted[0] as { user_id: string }).user_id, otherId);
});

test("a reply notifies the parent commenter instead of sibling commenters", async () => {
    const { database, inserted, queries } = createSql({
        post: { fight_id: fightId, author_id: otherId },
        parent: { author_id: thirdId },
        members: [
            { user_id: otherId, fight_id: fightId },
            { user_id: thirdId, fight_id: fightId },
        ],
        actor: { handle: "alex", display_name: "Alex" },
        recipients: [
            {
                user_id: thirdId,
                locale: "en",
                feed_post: true,
                post_comment: true,
                comment_reply: true,
                post_reaction: true,
            },
            {
                user_id: otherId,
                locale: "en",
                feed_post: true,
                post_comment: true,
                comment_reply: true,
                post_reaction: true,
            },
        ],
    });
    await enqueueFightFeedCommentNotifications(database, {
        postId,
        commentId,
        parentId,
        actorId,
    });
    assert.equal(inserted.length, 2);
    const kinds = (inserted as Array<{ user_id: string; kind: string }>)
        .map((row) => `${row.user_id}:${row.kind}`)
        .sort();
    assert.deepEqual(kinds, [
        `${otherId}:post_comment`,
        `${thirdId}:comment_reply`,
    ]);
    assert.equal(
        queries.some(
            (sql) =>
                sql.includes("fight_post_comments") && sql.includes("parent"),
        ),
        false,
    );
});

test("a reaction notifies the post author once", async () => {
    const { database, inserted } = createSql({
        post: { fight_id: fightId, author_id: otherId },
        members: [{ user_id: otherId, fight_id: fightId }],
        actor: { handle: "alex", display_name: "Alex" },
        recipients: [
            {
                user_id: otherId,
                locale: "fr",
                feed_post: true,
                post_comment: true,
                comment_reply: true,
                post_reaction: true,
            },
        ],
    });
    await enqueueFightFeedReactionNotifications(database, { postId, actorId });
    assert.equal(inserted.length, 1);
    const row = inserted[0] as { kind: string; alert_body: string };
    assert.equal(row.kind, "post_reaction");
    assert.equal(row.alert_body, "Alex a réagi à ta publication.");
});

test("reacting to your own post does not enqueue", async () => {
    const { database, inserted } = createSql({
        post: { fight_id: fightId, author_id: actorId },
    });
    await enqueueFightFeedReactionNotifications(database, { postId, actorId });
    assert.equal(inserted.length, 0);
});

test("a comment routes to a fight the recipient can open", async () => {
    const { database, inserted, queries } = createSql({
        post: { fight_id: fightId, author_id: otherId },
        members: [{ user_id: otherId, fight_id: siblingFightId }],
        actor: { handle: "alex", display_name: "Alex" },
        recipients: [
            {
                user_id: otherId,
                locale: "en",
                feed_post: true,
                post_comment: true,
                comment_reply: true,
                post_reaction: true,
            },
        ],
    });
    await enqueueFightFeedCommentNotifications(database, {
        postId,
        commentId,
        parentId: null,
        actorId,
    });
    assert.equal(inserted.length, 1);
    const row = inserted[0] as { fight_id: string; route: string };
    assert.equal(row.fight_id, siblingFightId);
    assert.equal(new URL(row.route, "https://fitfight.app").pathname, `/fights/${siblingFightId}`);
    assert.equal(new URL(row.route, "https://fitfight.app").searchParams.get("post"), postId);
    const access = queries.find(
        (sql) =>
            sql.includes("from public.fight_members") &&
            sql.includes("fight_post_channels"),
    );
    assert.ok(access);
    assert.match(access ?? "", /series_id/);
    assert.match(access ?? "", /fight_post_channels/);
});

test("a mention names the person and skips the author", async () => {
    const { database, inserted } = createSql({
        members: [{ user_id: otherId, fight_id: fightId }],
        actor: { handle: "alex", display_name: "Alex" },
        recipients: [
            {
                user_id: otherId,
                locale: "en",
                feed_post: true,
                post_comment: true,
                comment_reply: true,
                post_reaction: true,
            },
        ],
    });
    await enqueueMentionNotifications(database, {
        actorId,
        postId,
        userIds: [actorId, otherId],
        preferredFightId: fightId,
    });
    assert.equal(inserted.length, 1);
    const row = inserted[0] as {
        user_id: string;
        kind: string;
        copy_key: string;
        alert_body: string;
        route: string;
    };
    assert.equal(row.user_id, otherId);
    assert.equal(row.kind, "mention");
    assert.equal(row.copy_key, "mention_post");
    assert.equal(row.alert_body, "Alex tagged you in a post.");
    assert.doesNotMatch(row.alert_body, /score/i);
    assert.doesNotMatch(row.alert_body, /step/i);
    assert.equal(row.route, `/fights/${fightId}?post=${postId}`);
});

test("a comment mention names the person and skips a matching post-comment alert", async () => {
    const { database, inserted } = createSql({
        post: { fight_id: fightId, author_id: otherId },
        members: [{ user_id: otherId, fight_id: fightId }],
        actor: { handle: "alex", display_name: "Alex" },
        recipients: [
            {
                user_id: otherId,
                locale: "fr",
                feed_post: true,
                post_comment: true,
                comment_reply: true,
                post_reaction: true,
            },
        ],
    });
    await enqueueMentionNotifications(database, {
        actorId,
        postId,
        commentId,
        userIds: [otherId],
        preferredFightId: fightId,
    });
    await enqueueFightFeedCommentNotifications(database, {
        postId,
        commentId,
        parentId: null,
        actorId,
        skipUserIds: [otherId],
    });
    assert.equal(inserted.length, 1);
    const row = inserted[0] as {
        kind: string;
        copy_key: string;
        alert_body: string;
        route: string;
    };
    assert.equal(row.kind, "mention");
    assert.equal(row.copy_key, "mention_comment");
    assert.equal(row.alert_body, "Alex t’a mentionné dans un commentaire.");
    assert.equal(
        row.route,
        `/fights/${fightId}?post=${postId}&comment=${commentId}`,
    );
});

test("a tagged fight member is not also sent the generic post alert", async () => {
    const { database, inserted } = createSql({
        members: [{ user_id: otherId, fight_id: fightId }],
        actor: { handle: "alex", display_name: "Alex" },
        recipients: [
            {
                user_id: otherId,
                locale: "en",
                feed_post: true,
                post_comment: true,
                comment_reply: true,
                post_reaction: true,
            },
        ],
    });
    await enqueueFightFeedPostNotifications(database, {
        fightId,
        postId,
        actorId,
        skipUserIds: [otherId],
    });
    assert.equal(inserted.length, 0);
});

test("mention resolution is skipped when nobody is tagged", async () => {
    const { database, queries } = createSql({});
    assert.deepEqual(
        await eligibleMentionUserIds(database, actorId, [], [], [fightId]),
        [],
    );
    assert.equal(queries.length, 0);
});
