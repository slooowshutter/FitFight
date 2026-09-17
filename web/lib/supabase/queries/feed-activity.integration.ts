import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { randomJoinCode } from "@/lib/domain/fights/join-code";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { listFeedActivityQuerySchema } from "@/lib/types/feed/feed-activity";
import { fightPostResponseSchema } from "@/lib/types/feed/fight-post";
import { listFeedActivity } from "./feed-activity-supabase-query";
import { getFightPost, listFightPosts } from "./fight-posts-supabase-query";
import { listFightPostComments } from "./fight-post-engagement-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 1 });
after(() => database.end());

test("activity retains membership history, links older posts, and enforces current access", async (t) => {
    const users = Array.from({ length: 5 }, () => randomUUID());
    const [owner, peer, invited, outsider, siblingMember] = users;
    const fightId = randomUUID(), siblingId = randomUUID(), seriesId = randomUUID();
    const postId = randomUUID(), newerPostId = randomUUID(), commentId = randomUUID();
    t.after(async () => {
        await database`delete from public.fights where id in (${fightId}, ${siblingId})`;
        await database`delete from public.fight_series where id = ${seriesId}`;
        await database`delete from auth.users where id in ${database(users)}`;
    });
    for (const user of users) await database`insert into auth.users (id) values (${user})`;
    await database`
        insert into public.fight_series (id, owner_id, name, visibility, duration_seconds, time_zone, join_code)
        values (${seriesId}, ${owner}, 'Activity series', 'invite_only', 604800, 'UTC', ${randomJoinCode()})
    `;
    await database`
        insert into public.fights (id, owner_id, name, series_id, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy)
        values
            (${fightId}, ${owner}, 'Goodwin', ${seriesId}, 'live', now(), now() + interval '7 days', 'UTC', 'highest_total', 'shared'),
            (${siblingId}, ${owner}, 'Goodwin next round', ${seriesId}, 'live', now() + interval '7 days', now() + interval '14 days', 'UTC', 'highest_total', 'shared')
    `;
    await database`
        insert into public.fight_members (fight_id, user_id, state) values
            (${fightId}, ${owner}, 'accepted'), (${fightId}, ${peer}, 'invited'),
            (${fightId}, ${invited}, 'invited'), (${siblingId}, ${siblingMember}, 'accepted')
    `;
    await database`update public.fight_members set state = 'accepted', accepted_at = now() where fight_id = ${fightId} and user_id = ${peer}`;
    await database`insert into public.fight_posts (id, fight_id, audience, author_id, body, created_at) values
        (${postId}, ${fightId}, 'fight', ${owner}, 'Original post', '2026-09-15T00:00:00.123456Z'),
        (${newerPostId}, ${fightId}, 'fight', ${owner}, 'Newer post', '2026-09-15T01:00:00Z')`;
    await database`insert into public.fight_post_comments (id, post_id, author_id, body) values (${commentId}, ${postId}, ${peer}, 'A new comment')`;
    await database`insert into public.fight_post_reactions (post_id, user_id, emoji) values (${postId}, ${peer}, '❤️')`;
    await database`insert into private.notification_preferences (user_id, post_comment, post_reaction) values (${owner}, false, false)`;
    await database`insert into private.fight_membership_events (fight_id, user_id, state, occurred_at)
        values (${fightId}, ${peer}, 'invited', null)`;
    const all = await listFeedActivity(owner, { limit: 80 }, database);
    assert.ok(all.events.some((e) => e.kind === 'post_comment' && e.comment_id === commentId && e.post_id === postId));
    assert.ok(all.events.some((e) => e.kind === 'post_reaction' && e.body === '❤️'));
    const invitation = all.events.find((e) => e.kind === 'invited' && e.subject?.user_id === peer);
    assert.ok(invitation?.occurred_at);
    assert.equal(invitation.actor.user_id, owner);
    assert.ok(all.events.some((e) => e.kind === 'accepted' && e.actor.user_id === peer && e.occurred_at));
    assert.equal(all.events.at(-1)?.occurred_at, null, 'Unknown invitation times sort last without being invented');
    assert.deepEqual((await listFeedActivity(outsider, { limit: 80 }, database)).events, []);
    const invitee = await listFeedActivity(invited, { limit: 80 }, database);
    assert.equal(invitee.events.length, 1);
    assert.equal(invitee.events[0].subject?.user_id, invited);
    assert.equal(invitee.events[0].kind, 'invited');

    const firstPage = await listFightPosts(owner, undefined, { limit: 1 }, database);
    assert.equal(firstPage.posts[0].id, newerPostId);
    assert.equal(fightPostResponseSchema.parse(await getFightPost(owner, postId, database)).post.id, postId);
    assert.equal((await getFightPost(siblingMember, postId, database)).post.id, postId);
    const siblingActivity = await listFeedActivity(siblingMember, { limit: 80 }, database);
    assert.ok(siblingActivity.events.some((e) => e.comment_id === commentId && e.fight_id === siblingId));
    for (const viewer of [invited, outsider]) {
        await assert.rejects(getFightPost(viewer, postId, database), { status: 403 });
    }

    const ids: string[] = [];
    let cursor: string | null = null;
    do {
        const page = await listFeedActivity(owner, listFeedActivityQuerySchema.parse({ limit: 1, cursor: cursor ?? undefined }), database);
        assert.equal(page.events.length, 1);
        ids.push(page.events[0].id);
        cursor = page.next_cursor;
    } while (cursor !== null);
    assert.deepEqual(ids, all.events.map((e) => e.id));
    assert.equal(new Set(ids).size, ids.length);

    const pageCommentIds = Array.from({ length: 42 }, () => randomUUID()).sort();
    await database`insert into public.fight_post_comments ${database(pageCommentIds.map((id) => ({
        id, post_id: newerPostId, author_id: peer, body: 'A paginated comment',
    })))}`;
    for (const sort of [undefined, 'recent', 'comments'] as const) {
        const expected = sort === undefined ? pageCommentIds : [...pageCommentIds].reverse();
        const firstComments = await listFightPostComments(owner, newerPostId, { limit: 40, sort }, database);
        assert.equal(firstComments.comments.length, 40);
        assert.ok(firstComments.next_cursor);
        for (const cursor of [firstComments.next_cursor, firstComments.next_cursor.replace(/(\.\d{3})\d+Z/, '$1Z')]) {
            const secondComments = await listFightPostComments(owner, newerPostId, { limit: 40, cursor, sort }, database);
            assert.deepEqual(secondComments.comments.map((c) => c.id), expected.slice(40));
            assert.equal(secondComments.next_cursor, null, 'Targeted comments must reach the last page in every sort with new and legacy cursors');
        }
    }
    await database`update public.fight_posts set created_at = '2026-09-15T00:00:00.123456Z'::timestamptz where id in (${postId}, ${newerPostId})`;
    const tiedPosts = await listFightPosts(owner, undefined, { limit: 1 }, database);
    assert.ok(tiedPosts.next_cursor);
    for (const cursor of [tiedPosts.next_cursor, tiedPosts.next_cursor.replace(/(\.\d{3})\d+Z/, '$1Z')]) {
        const nextPosts = await listFightPosts(owner, undefined, { limit: 1, cursor }, database);
        assert.equal(nextPosts.posts.length, 1);
        assert.notEqual(nextPosts.posts[0].id, tiedPosts.posts[0].id);
        assert.equal(nextPosts.next_cursor, null, 'Live refresh must not skip older posts with tied timestamps');
    }

    const [before] = await database`select count(*)::int as n from private.fight_membership_events where fight_id = ${fightId}`;
    await database`update public.fight_members set current_value = 2345 where fight_id = ${fightId} and user_id = ${peer}`;
    const [afterScore] = await database`select count(*)::int as n from private.fight_membership_events where fight_id = ${fightId}`;
    assert.equal(afterScore.n, before.n, 'A score refresh is not another acceptance');
    await assert.rejects(database.begin(async (sql) => {
        await sql`update public.fight_members set state = 'withdrawn' where fight_id = ${fightId} and user_id = ${peer}`;
        throw new Error('rollback membership');
    }), /rollback membership/);
    const [afterRollback] = await database`select count(*)::int as n from private.fight_membership_events where fight_id = ${fightId}`;
    assert.equal(afterRollback.n, before.n);

    await database`insert into private.feed_blocks (blocker_id, blocked_id) values (${peer}, ${owner})`;
    const blocked = await listFeedActivity(owner, { limit: 80 }, database);
    assert.ok(blocked.events.every((e) => e.actor.user_id !== peer && e.subject?.user_id !== peer));
    await assert.rejects(getFightPost(peer, postId, database), { status: 404 });
    await database`delete from private.feed_blocks where blocker_id = ${peer} and blocked_id = ${owner}`;
    await database`update public.fight_members set state = 'withdrawn' where fight_id = ${fightId} and user_id = ${peer}`;
    assert.deepEqual((await listFeedActivity(peer, { limit: 80 }, database)).events, []);
    await assert.rejects(getFightPost(peer, postId, database), { status: 403 });

    await database`delete from public.fight_posts where id = ${postId}`;
    assert.ok((await listFeedActivity(owner, { limit: 80 }, database)).events.every((e) => e.post_id !== postId));
    await assert.rejects(getFightPost(owner, postId, database), { status: 404 });
});
