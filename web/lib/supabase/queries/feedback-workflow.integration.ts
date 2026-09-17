import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { feedbackDetailResponseSchema, type ChangeFeedbackStatusRequest } from "@/lib/types/feedback/feedback";
import { sendFeedbackFix } from "@/lib/cursor/send-feedback-fix";
import { changeFeedbackStatus, createFeedbackComment, getFeedbackPost, listFeedbackPosts } from "./feedback-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 4 });
after(() => database.end());

test("feedback progress preserves legacy writes and commits exactly one public update", async (t) => {
    const admin = randomUUID();
    const author = randomUUID();
    const viewer = randomUUID();
    const postId = randomUUID();
    const otherPostId = randomUUID();
    const oldAdmin = process.env.FITFIGHT_FEEDBACK_ADMIN_USER_ID;
    const oldEnabled = process.env.FITFIGHT_FEEDBACK_WORKFLOW_ENABLED;
    process.env.FITFIGHT_FEEDBACK_ADMIN_USER_ID = admin;
    process.env.FITFIGHT_FEEDBACK_WORKFLOW_ENABLED = "true";
    await assert.rejects(database.begin(async (sql) => {
        await sql`set local role authenticated`;
        await sql`
            insert into public.feedback_comments (post_id, body, workflow_status)
            values (${postId}, 'A forged public update.', 'approved')
        `;
    }), { code: "42501" });
    t.after(async () => {
        if (oldAdmin === undefined) delete process.env.FITFIGHT_FEEDBACK_ADMIN_USER_ID;
        else process.env.FITFIGHT_FEEDBACK_ADMIN_USER_ID = oldAdmin;
        if (oldEnabled === undefined) delete process.env.FITFIGHT_FEEDBACK_WORKFLOW_ENABLED;
        else process.env.FITFIGHT_FEEDBACK_WORKFLOW_ENABLED = oldEnabled;
        await database`delete from auth.users where id in ${database([admin, author, viewer])}`;
    });
    for (const id of [admin, author, viewer]) {
        await database`insert into auth.users (id) values (${id})`;
        await database`update public.profiles set handle = ${`wf_${id.slice(0, 8)}`} where user_id = ${id}`;
    }
    for (const id of [postId, otherPostId]) {
        await database`
            insert into public.feedback_posts (id, author_id, kind, title, body)
            values (${id}, ${author}, 'feature', 'Request progress', 'Show the progress of this request.')
        `;
    }
    const original = await createFeedbackComment(viewer, postId, { body: "I would use this." }, database);
    assert.deepEqual(Object.keys(original.comment).sort(), ["id", "body", "author_handle", "created_at", "metadata"].sort());
    assert.equal((await getFeedbackPost(viewer, postId, database)).post.workflow_status, "submitted");
    await assert.rejects(database`
        insert into public.feedback_comments (post_id, body) values (${postId}, 'Missing author')
    `, { code: "23514" });
    await assert.rejects(database`
        update public.feedback_posts set workflow_status = 'invented' where id = ${postId}
    `, { code: "23514" });
    await assert.rejects(database`
        insert into public.feedback_comments (post_id, body, workflow_status)
        values (${postId}, 'Invalid status', 'invented')
    `, { code: "23514" });

    const approval: ChangeFeedbackStatusRequest = {
        expected_status: "submitted", status: "approved", operation_id: randomUUID(),
    };
    await assert.rejects(changeFeedbackStatus(viewer, postId, approval, database), { status: 403 });
    process.env.FITFIGHT_FEEDBACK_WORKFLOW_ENABLED = "false";
    await assert.rejects(changeFeedbackStatus(admin, postId, approval, database), { status: 503 });
    process.env.FITFIGHT_FEEDBACK_WORKFLOW_ENABLED = "true";
    const parallel = await Promise.all([
        changeFeedbackStatus(admin, postId, approval, database),
        changeFeedbackStatus(admin, postId, approval, database),
    ]);
    assert.deepEqual(parallel, [{ workflow_status: "approved" }, { workflow_status: "approved" }]);
    await changeFeedbackStatus(admin, postId, {
        ...approval, expected_status: "approved", operation_id: randomUUID(),
    }, database);
    let detail = await getFeedbackPost(viewer, postId, database);
    assert.equal(detail.comments.length, 2);
    assert.equal(detail.post.comment_count, 2);
    const system = detail.comments.find((comment) => comment.id === approval.operation_id);
    assert.equal(system?.actor_id, admin);
    assert.equal(system?.author_handle, "FitFight");
    assert.equal(system?.body, "Approved by Marc for build.");
    assert.deepEqual(system?.metadata, {});
    feedbackDetailResponseSchema.parse({ ...detail, can_launch_fix: false, can_manage_status: false });

    await assert.rejects(changeFeedbackStatus(admin, postId, {
        expected_status: "submitted", status: "building", operation_id: randomUUID(),
    }, database), { status: 409 });
    await assert.rejects(changeFeedbackStatus(admin, otherPostId, approval, database), { status: 409 });
    await assert.rejects(changeFeedbackStatus(admin, postId, {
        ...approval, status: "building",
    }, database), { status: 409 });
    await assert.rejects(changeFeedbackStatus(admin, postId, {
        expected_status: "approved", status: "building", operation_id: original.comment.id,
    }, database), { status: 409 });

    await database.unsafe(`alter table public.feedback_comments add constraint feedback_workflow_test_failure
        check (post_id <> '${postId}'::uuid or workflow_status <> 'testing') not valid`);
    try {
        await assert.rejects(changeFeedbackStatus(admin, postId, {
            expected_status: "approved", status: "testing", operation_id: randomUUID(),
        }, database), { code: "23514" });
        assert.equal((await getFeedbackPost(viewer, postId, database)).post.workflow_status, "approved");
    } finally {
        await database`alter table public.feedback_comments drop constraint feedback_workflow_test_failure`;
    }

    await database`delete from auth.users where id = ${admin}`;
    await assert.rejects(changeFeedbackStatus(admin, postId, {
        expected_status: "approved", status: "testing", operation_id: randomUUID(),
    }, database), { status: 404 });
    assert.equal((await getFeedbackPost(viewer, postId, database)).post.workflow_status, "approved");
    await database`insert into auth.users (id) values (${admin})`;
    await database`update public.profiles set handle = ${`wf_${admin.slice(0, 8)}`} where user_id = ${admin}`;

    await t.test("failed Send retains approval; successful Send adds Being built without repeating approval", async () => {
        await changeFeedbackStatus(admin, postId, {
            expected_status: "approved", status: "submitted", operation_id: randomUUID(),
        }, database);
        const change = (user: string, post: string, input: ChangeFeedbackStatusRequest) =>
            changeFeedbackStatus(user, post, input, database);
        await assert.rejects(sendFeedbackFix(admin, await getFeedbackPost(admin, postId, database), {}, async () => {
            assert.equal((await getFeedbackPost(viewer, postId, database)).post.workflow_status, "approved");
            throw new Error("Provider failed");
        }, change), /Provider failed/);
        const before = await getFeedbackPost(admin, postId, database);
        const launched = await sendFeedbackFix(admin, before, {}, async () => ({
            agent_id: "private-provider-id", agent_url: "https://cursor.com/agents/private-provider-id",
        }), change);
        assert.equal(launched.agent_id, "private-provider-id");
        detail = await getFeedbackPost(viewer, postId, database);
        assert.equal(detail.post.workflow_status, "building");
        assert.equal(detail.comments.length, before.comments.length + 1);
        assert.equal(JSON.stringify(detail.comments).includes("private-provider-id"), false);
        const replayApproval = before.comments.find((comment) => comment.workflow_status === "approved");
        assert.ok(replayApproval);
        assert.deepEqual(await changeFeedbackStatus(admin, postId, {
            expected_status: "submitted", status: "approved", operation_id: replayApproval.id,
        }, database), { workflow_status: "building" });
    });

    await t.test("public updates stay visible while hidden actors and normal comments stay hidden", async () => {
        await createFeedbackComment(admin, postId, { body: "An ordinary admin comment." }, database);
        await database`insert into private.feedback_blocks (blocker_id, blocked_id) values (${viewer}, ${admin})`;
        const hidden = await getFeedbackPost(viewer, postId, database);
        assert.equal(hidden.comments.some((comment) => comment.body === "An ordinary admin comment."), false);
        assert.ok(hidden.comments.some((comment) => comment.workflow_status === "approved"));
        assert.ok(hidden.comments.filter((comment) => comment.workflow_status).every((comment) => comment.actor_id === null));
        assert.equal(hidden.post.comment_count, hidden.comments.length);
        const listed = await listFeedbackPosts(viewer, {}, database);
        assert.equal(listed.posts.find((post) => post.id === postId)?.comment_count, hidden.comments.length);
        await database`delete from private.feedback_blocks where blocker_id = ${viewer} and blocked_id = ${admin}`;
        await database`update public.profiles set deleted_at = now() where user_id = ${admin}`;
        const deleted = await getFeedbackPost(viewer, postId, database);
        assert.equal(deleted.comments.some((comment) => comment.actor_id === admin), false);
        assert.equal(deleted.comments.some((comment) => comment.body === "An ordinary admin comment."), false);
        await database`update public.profiles set deleted_at = null where user_id = ${admin}`;
    });

    await t.test("system comments do not consume the user-comment daily limit", async () => {
        await database`
            insert into public.feedback_comments (post_id, author_id, body, workflow_status)
            select ${postId}, ${admin}, 'Approved by Marc for build.', 'approved' from generate_series(1, 30)
        `;
        await createFeedbackComment(admin, postId, { body: "User comments still work." }, database);
        await database`
            insert into public.feedback_comments (post_id, author_id, body)
            select ${postId}, ${admin}, 'An ordinary comment.' from generate_series(1, 28)
        `;
        await assert.rejects(createFeedbackComment(admin, postId, { body: "Over the limit." }, database), { status: 429 });
    });

    await database`delete from auth.users where id = ${admin}`;
    const afterDeletion = await getFeedbackPost(viewer, postId, database);
    assert.equal(afterDeletion.post.workflow_status, "building");
    assert.ok(afterDeletion.comments.some((comment) => comment.workflow_status === "building"));
    assert.equal(afterDeletion.comments.some((comment) => comment.workflow_status === "approved"), false);
    assert.equal(afterDeletion.post.comment_count, afterDeletion.comments.length);
    await database`delete from public.feedback_posts where id = ${postId}`;
    const [{ count }] = await database`select count(*)::int as count from public.feedback_comments where post_id = ${postId}`;
    assert.equal(count, 0);
});
