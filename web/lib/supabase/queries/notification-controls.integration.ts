import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { defaultNotificationPreferences, updateNotificationPreferencesRequestSchema } from "@/lib/types/notifications/notification-preferences";
import { notificationDeliveryRowSchema } from "@/lib/types/notifications/notification-delivery";
import { readNotificationPreferences, updateNotificationPreferences } from "./notification-preferences-supabase-query";
import { enqueueFightFeedPostNotifications, enqueueFightFeedReactionNotifications, enqueueFightFeedCommentNotifications } from "./feed-social-notifications-supabase-query";
import { enqueueScheduledNotifications } from "./scheduled-notifications-supabase-query";
import { enqueueAwaitingFinalSyncNotifications } from "./notification-intents-supabase-query";
import { readNotificationContent } from "./notification-content-supabase-query";
import { processNotificationOutbox } from "./process-notification-outbox-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 3 });
after(() => database.end());

test("notification controls preserve old clients and batch activity without losing opt-outs", async (t) => {
    const users = [randomUUID(), randomUUID(), randomUUID()];
    const [owner, peer, third] = users;
    const fightId = randomUUID(), postId = randomUUID(), newPostId = randomUUID();
    const at = new Date("2026-09-20T17:00:00Z");
    t.mock.method(Date, "now", () => at.getTime());
    t.after(async () => {
        await database`delete from public.fights where id = ${fightId}`;
        await database`delete from auth.users where id in ${database(users)}`;
    });
    for (const user of users) {
        await database`insert into auth.users (id) values (${user})`;
        await database`update public.profiles set handle = ${'notif_' + user.slice(0, 8)}, display_name = 'Private Real Name', time_zone = 'Europe/Paris' where id = ${user}`;
    }
    await database`insert into public.fights (id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy)
        values (${fightId}, ${owner}, 'Weekend Warriors', 'live', '2026-09-01T17:00:00Z', '2026-09-21T17:00:00Z', 'Europe/Paris', 'highest_total', 'shared')`;
    for (const user of users) await database`insert into public.fight_members (fight_id, user_id, state) values (${fightId}, ${user}, 'accepted')`;
    await database`insert into public.fight_posts (id, fight_id, audience, author_id, body) values
        (${postId}, ${fightId}, 'fight', ${owner}, 'Morning walk'), (${newPostId}, ${fightId}, 'fight', ${peer}, 'Hello walkers')`;
    await database`insert into public.fight_post_reactions (post_id, user_id, emoji) values (${postId}, ${peer}, '🔥'), (${postId}, ${third}, '❤️')`;

    assert.deepEqual(await readNotificationPreferences(owner, database), defaultNotificationPreferences);
    const legacyOff = updateNotificationPreferencesRequestSchema.parse({ challenge_reminder: false });
    const off = await updateNotificationPreferences(owner, legacyOff, database);
    assert.equal(off.final_sync, false);
    assert.equal(off.fight_ended, false);
    assert.equal(off.fight_finalized, false);
    const legacyOn = await updateNotificationPreferences(owner, { challenge_reminder: true }, database);
    assert.equal(legacyOn.fight_ended, true);
    assert.equal(legacyOn.final_sync, true);
    await Promise.all([
        updateNotificationPreferences(owner, { fight_ended: false, feed_post: true }, database),
        updateNotificationPreferences(owner, { daily_status: false, mention: false }, database),
    ]);
    const preserved = await readNotificationPreferences(owner, database);
    assert.equal(preserved.feed_post, true);
    assert.equal(preserved.mention, false);
    assert.equal(preserved.fight_ended, false);
    await updateNotificationPreferences(owner, { enabled: false }, database);
    await enqueueFightFeedReactionNotifications(database, { postId, actorId: peer });
    const [muted] = await database`select count(*)::int as n from private.notification_intents where user_id = ${owner}`;
    assert.equal(muted.n, 0);
    await updateNotificationPreferences(owner, { enabled: true }, database);
    assert.equal((await readNotificationPreferences(owner, database)).mention, false);

    await enqueueFightFeedReactionNotifications(database, { postId, actorId: peer });
    await enqueueFightFeedReactionNotifications(database, { postId, actorId: third });
    await enqueueFightFeedReactionNotifications(database, { postId, actorId: third });
    await enqueueFightFeedPostNotifications(database, { fightId, postId: newPostId, actorId: peer });
    const raw = await database`select kind, not_before, digest_on::text, alert_body from private.notification_intents where user_id = ${owner}`;
    assert.equal(raw.length, 3, "Repeated reaction changes must not create extra notifications");
    assert.ok(raw.every((row) => row.not_before.toISOString() === "2026-09-20T18:00:00.000Z"));
    assert.ok(raw.every((row) => row.alert_body.includes("@notif_") && !row.alert_body.includes("Private Real Name")));
    await enqueueScheduledNotifications(database, at);
    const [early] = await database`select count(*)::int as n from private.notification_intents where user_id = ${owner} and kind = 'social_digest'`;
    assert.equal(early.n, 0);
    await Promise.all([
        enqueueScheduledNotifications(database, new Date("2026-09-20T18:00:00Z")),
        enqueueScheduledNotifications(database, new Date("2026-09-20T18:00:00Z")),
    ]);
    const digests = await database`select * from private.notification_intents where user_id = ${owner} and kind = 'social_digest'`;
    assert.equal(digests.length, 1, "Concurrent jobs must create only one evening summary");
    const delivery = notificationDeliveryRowSchema.parse({
        ...digests[0], fight_state: "live", fight_name: "Weekend Warriors", owner_handle: "owner",
        ends_at: "2026-09-21T17:00:00Z", sync_deadline: "2026-09-22T17:00:00Z", time_zone: "Europe/Paris",
        member_state: "accepted", final_steps_complete: false, preferences: await readNotificationPreferences(owner, database),
    });
    const content = await readNotificationContent(delivery, "en", database);
    assert.ok(content?.body.includes("and 1 other reacted"));
    assert.ok(content?.body.includes("1 new post"));
    assert.ok(content?.route.endsWith("activity=1"));
    assert.equal(content?.imageUrl, null);
    const reactionOnly = await readNotificationContent({ ...delivery, preferences: { ...delivery.preferences, feed_post: false } }, "en", database);
    assert.ok(!reactionOnly?.body.includes("new post"));
    assert.ok(reactionOnly?.route.includes(`post=${postId}`));
    await database`insert into private.feed_blocks (blocker_id, blocked_id) values (${owner}, ${peer}), (${owner}, ${third})`;
    assert.equal(await readNotificationContent(delivery, "en", database), null, "Delayed pushes must recheck blocks");
    await database`delete from private.feed_blocks where blocker_id = ${owner}`;
    await database`delete from public.fight_post_reactions where post_id = ${postId}`;
    assert.equal(await readNotificationContent({ ...delivery, preferences: { ...delivery.preferences, feed_post: false } }, "en", database), null);

    await updateNotificationPreferences(owner, { enabled: false }, database);
    const processed = await processNotificationOutbox(new Date("2026-09-20T18:00:00Z"), database);
    assert.ok(processed.skipped >= 1);
    const [digestStatus] = await database`select status, skip_reason from private.notification_intents where id = ${digests[0].id}`;
    assert.equal(digestStatus.status, "skipped");
    assert.equal(digestStatus.skip_reason, "muted");

    await updateNotificationPreferences(owner, { enabled: true, ending_week: true }, database);
    await database`update public.fights set starts_at = '2026-08-28T17:00:00Z', ends_at = '2026-09-27T17:00:00Z' where id = ${fightId}`;
    await enqueueScheduledNotifications(database, at);
    const [week] = await database`select count(*)::int as n from private.notification_intents where user_id = ${owner} and kind = 'ending_week'`;
    assert.equal(week.n, 1);
    const [others] = await database`select count(*)::int as n from private.notification_intents where user_id <> ${owner} and fight_id = ${fightId} and kind = 'ending_week'`;
    assert.equal(others.n, 0, "One-week reminder is opt-in");

    await enqueueAwaitingFinalSyncNotifications(database, fightId, at.toISOString(), [
        { user_id: owner, final_steps_complete: false }, { user_id: peer, final_steps_complete: true },
    ]);
    const final = await database`select user_id, kind from private.notification_intents where fight_id = ${fightId} and kind in ('final_sync', 'grace_reminder')`;
    assert.deepEqual(final.map((row) => [row.user_id, row.kind]), [[owner, "final_sync"]]);

    await updateNotificationPreferences(owner, { post_comment: true }, database);
    const commentId = randomUUID();
    await database`insert into public.fight_post_comments (id, post_id, author_id, body) values (${commentId}, ${postId}, ${peer}, 'See you tomorrow')`;
    await enqueueFightFeedCommentNotifications(database, { postId, commentId, parentId: null, actorId: peer, skipUserIds: [owner] });
    const [comment] = await database`select * from private.notification_intents where user_id = ${owner} and comment_id = ${commentId}`;
    const commentContent = await readNotificationContent({ ...delivery, ...comment, preferences: await readNotificationPreferences(owner, database) }, "en", database);
    assert.ok(commentContent?.title.startsWith("@notif_"));
    assert.ok(commentContent?.body.includes("See you tomorrow"));
    assert.ok(commentContent?.route.endsWith(`comment=${commentId}`));
    await database`delete from public.fight_posts where id = ${newPostId}`;
    assert.equal(await readNotificationContent(delivery, "en", database), null, "Deleted posts and removed reactions must disappear from a delayed summary");

    at.setTime(Date.parse("2026-10-24T18:01:00Z"));
    const dstPost = randomUUID();
    await database`insert into public.fight_posts (id, fight_id, audience, author_id, body)
        values (${dstPost}, ${fightId}, 'fight', ${peer}, 'After the evening cutoff')`;
    await enqueueFightFeedPostNotifications(database, { fightId, postId: dstPost, actorId: peer });
    const [dst] = await database`select not_before, digest_on::text from private.notification_intents where user_id = ${owner} and post_id = ${dstPost}`;
    assert.equal(dst.digest_on, "2026-10-25");
    assert.equal(dst.not_before.toISOString(), "2026-10-25T19:00:00.000Z", "The evening cutoff must follow the saved zone across daylight-saving changes");

});
