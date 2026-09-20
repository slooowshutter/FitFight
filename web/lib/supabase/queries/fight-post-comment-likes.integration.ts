import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import {
    createFightPostComment,
    deleteFightPostComment,
    listFightPostComments,
    setFightPostCommentLike,
} from "./fight-post-engagement-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 1 });
after(() => database.end());

test("comment likes persist, preserve old comment reads, respect visibility and cascade", async (t) => {
    const owner = randomUUID(), commenter = randomUUID(), viewer = randomUUID();
    const postId = randomUUID(), privatePostId = randomUUID(), privateCommentId = randomUUID();
    t.after(async () => {
        await database`delete from public.fight_posts where id in (${postId}, ${privatePostId})`;
        await database`delete from auth.users where id in (${owner}, ${commenter}, ${viewer})`;
    });
    for (const userId of [owner, commenter, viewer]) {
        await database`insert into auth.users (id) values (${userId})`;
    }
    await database`
        insert into public.fight_posts (id, audience, app_wide, author_id, body) values
            (${postId}, 'main', true, ${owner}, 'A broadcast'),
            (${privatePostId}, 'main', false, ${owner}, 'A private post')
    `;
    await database`
        insert into public.fight_post_comments (id, post_id, author_id, body)
        values (${privateCommentId}, ${privatePostId}, ${owner}, 'Private comment')
    `;
    // This is the installed client's unchanged comment creation request.
    const created = await createFightPostComment(commenter, postId, { body: "A comment" }, database);
    const commentId = created.comment.id;
    assert.equal(created.comment.like_count, 0);
    assert.equal(created.comment.liked_by_me, false);
    const original = await listFightPostComments(viewer, postId, { limit: 40 }, database);
    for (const desired of [true, true, false, false, true]) {
        assert.deepEqual(await setFightPostCommentLike(viewer, postId, commentId, desired, database), {
            like_count: desired ? 1 : 0,
            liked_by_me: desired,
        });
    }
    assert.deepEqual(await setFightPostCommentLike(owner, postId, commentId, true, database), {
        like_count: 2,
        liked_by_me: true,
    });
    for (const sort of [undefined, "recent", "comments"] as const) {
        const listed = await listFightPostComments(viewer, postId, { limit: 40, sort }, database);
        assert.deepEqual(listed.comments, [{ ...original.comments[0], like_count: 2, liked_by_me: true }]);
        assert.equal(listed.next_cursor, original.next_cursor);
    }
    assert.equal((await listFightPostComments(commenter, postId, { limit: 40 }, database)).comments[0].liked_by_me, false);
    await assert.rejects(setFightPostCommentLike(viewer, privatePostId, privateCommentId, true, database), { status: 403 });
    await assert.rejects(setFightPostCommentLike(viewer, postId, privateCommentId, true, database), { status: 404 });
    await assert.rejects(setFightPostCommentLike(viewer, postId, randomUUID(), true, database), { status: 404 });

    await database`insert into private.feed_blocks (blocker_id, blocked_id) values (${viewer}, ${commenter})`;
    assert.deepEqual((await listFightPostComments(viewer, postId, { limit: 40 }, database)).comments, []);
    await assert.rejects(setFightPostCommentLike(viewer, postId, commentId, false, database), { status: 404 });
    await database`delete from private.feed_blocks where blocker_id = ${viewer}`;
    await database`insert into private.feed_blocks (blocker_id, blocked_id) values (${viewer}, ${owner})`;
    await assert.rejects(setFightPostCommentLike(viewer, postId, commentId, true, database), { status: 404 });
    await database`delete from private.feed_blocks where blocker_id = ${viewer}`;
    await database`insert into private.feed_blocks (blocker_id, blocked_id) values (${owner}, ${viewer})`;
    await assert.rejects(setFightPostCommentLike(viewer, postId, commentId, true, database), { status: 404 });
    await database`delete from private.feed_blocks where blocker_id = ${owner}`;

    await database`insert into private.feed_blocks (blocker_id, blocked_id) values (${commenter}, ${viewer})`;
    await assert.rejects(setFightPostCommentLike(viewer, postId, commentId, true, database), { status: 404 });
    assert.equal((await listFightPostComments(commenter, postId, { limit: 40 }, database)).comments[0].like_count, 1);
    await database`update public.profiles set deleted_at = now() where user_id = ${commenter}`;
    await assert.rejects(setFightPostCommentLike(viewer, postId, commentId, true, database), { status: 404 });
    await database`update public.profiles set deleted_at = null where user_id = ${commenter}`;
    await database`delete from auth.users where id = ${viewer}`;
    const [remaining] = await database`select count(*)::int as n from private.fight_post_comment_likes where comment_id = ${commentId}`;
    assert.equal(remaining.n, 1, "Account deletion removes that account's likes");

    const reply = await createFightPostComment(commenter, postId, { body: "Reply", parent_id: commentId }, database);
    await setFightPostCommentLike(owner, postId, reply.comment.id, true, database);
    const deleted = await deleteFightPostComment(commenter, postId, commentId, database);
    assert.deepEqual(deleted, { deleted: true, comment_count: 0 });
    const [afterDelete] = await database`select count(*)::int as n from private.fight_post_comment_likes where post_id = ${postId}`;
    assert.equal(afterDelete.n, 0, "Deleting a thread cascades its comment and reply likes");
    await assert.rejects(setFightPostCommentLike(owner, postId, commentId, true, database), { status: 404 });
});
