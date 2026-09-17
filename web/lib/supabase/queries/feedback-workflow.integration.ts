import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { createClient } from "@supabase/supabase-js";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { feedbackDetailResponseSchema, type ChangeFeedbackStatusRequest } from "@/lib/types/feedback/feedback";
import { sendFeedbackFix } from "@/lib/cursor/send-feedback-fix";
import { changeFeedbackStatus, createFeedbackComment, getFeedbackPost, listFeedbackPosts } from "./feedback-supabase-query";
import { closeDatabaseClientForTests } from "@/lib/supabase/postgres";
import { GET as readDetail } from "@/app/api/v1/feedback/[postID]/route";
import { POST as writeStatus } from "@/app/api/v1/feedback/[postID]/status/route";
import { POST as writeComment } from "@/app/api/v1/feedback/[postID]/comments/route";
import { POST as sendFix } from "@/app/api/v1/feedback/[postID]/fix-agent/route";

const env = databaseTestEnvironmentSchema.parse(process.env);
process.env.NEXT_PUBLIC_SUPABASE_URL = env.SUPABASE_TEST_URL;
process.env.SUPABASE_SECRET_KEY = env.SUPABASE_TEST_SERVICE_KEY;
const database = postgres(env.DATABASE_URL, { max: 4 });
after(() => database.end());
after(() => closeDatabaseClientForTests());

test("feedback progress preserves legacy writes and commits exactly one public update", async (t) => {
    const admin = randomUUID();
    const author = randomUUID();
    const viewer = randomUUID();
    const postId = randomUUID();
    const otherPostId = randomUUID();
    const oldAdmin = process.env.FITFIGHT_ADMIN_USER_ID;
    const oldEnabled = process.env.FITFIGHT_FEEDBACK_WORKFLOW_ENABLED;
    process.env.FITFIGHT_ADMIN_USER_ID = admin;
    process.env.FITFIGHT_FEEDBACK_WORKFLOW_ENABLED = "true";
    await assert.rejects(database.begin(async (sql) => {
        await sql`set local role authenticated`;
        await sql`
            insert into public.feedback_comments (post_id, body, workflow_status)
            values (${postId}, 'A forged public update.', 'approved')
        `;
    }), { code: "42501" });
    t.after(async () => {
        if (oldAdmin === undefined) delete process.env.FITFIGHT_ADMIN_USER_ID;
        else process.env.FITFIGHT_ADMIN_USER_ID = oldAdmin;
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
    assert.deepEqual(Object.keys(original.comment).sort(), ["id", "body", "author_id", "author_handle", "created_at", "metadata"].sort());
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
        await database`insert into private.profile_blocks (blocker_id, blocked_id) values (${admin}, ${viewer})`;
        const privateProfile = await getFeedbackPost(viewer, postId, database);
        assert.ok(privateProfile.comments.some((comment) => comment.workflow_status === "approved"));
        assert.equal(privateProfile.comments.some((comment) => comment.actor_id === admin), false);
        await database`delete from private.profile_blocks where blocker_id = ${admin} and blocked_id = ${viewer}`;
        await database`insert into private.feed_blocks (blocker_id, blocked_id) values (${viewer}, ${admin})`;
        const hiddenInFeed = await getFeedbackPost(viewer, postId, database);
        assert.equal(hiddenInFeed.comments.some((comment) => comment.actor_id === admin), false);
        await database`delete from private.feed_blocks where blocker_id = ${viewer} and blocked_id = ${admin}`;
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

test("authenticated feedback endpoints preserve old clients and reject forged admin identities", async (t) => {
    const auth = createClient(env.SUPABASE_TEST_URL, env.SUPABASE_TEST_SERVICE_KEY, {
        auth: { persistSession: false, autoRefreshToken: false },
    });
    const identities: { userId: string; token: string }[] = [];
    const previousAdmin = process.env.FITFIGHT_ADMIN_USER_ID;
    const previousEnabled = process.env.FITFIGHT_FEEDBACK_WORKFLOW_ENABLED;
    const previousCursor = process.env.CURSOR_API_KEY;
    const originalFetch = globalThis.fetch;
    t.after(async () => {
        globalThis.fetch = originalFetch;
        for (const [name, value] of Object.entries({
            FITFIGHT_ADMIN_USER_ID: previousAdmin,
            FITFIGHT_FEEDBACK_WORKFLOW_ENABLED: previousEnabled,
            CURSOR_API_KEY: previousCursor,
        })) {
            if (value === undefined) delete process.env[name];
            else process.env[name] = value;
        }
        if (identities.length) await database`delete from auth.users where id in ${database(identities.map((identity) => identity.userId))}`;
    });
    for (let index = 0; index < 2; index++) {
        const email = `feedback-${randomUUID()}@example.com`;
        const password = randomUUID();
        const created = await auth.auth.admin.createUser({
            email, password, email_confirm: true,
            user_metadata: { email: "marc@marclamy.com", handle: "marc" },
        });
        assert.equal(created.error, null);
        assert.ok(created.data.user);
        const client = createClient(env.SUPABASE_TEST_URL, env.SUPABASE_TEST_ANON_KEY, {
            auth: { persistSession: false, autoRefreshToken: false },
        });
        const login = await client.auth.signInWithPassword({ email, password });
        assert.equal(login.error, null);
        assert.ok(login.data.session);
        identities.push({ userId: created.data.user.id, token: login.data.session.access_token });
    }
    const [admin, viewer] = identities;
    process.env.FITFIGHT_ADMIN_USER_ID = admin.userId;
    process.env.FITFIGHT_FEEDBACK_WORKFLOW_ENABLED = "true";
    delete process.env.CURSOR_API_KEY;
    const postId = randomUUID();
    await database`
        insert into public.feedback_posts (id, author_id, kind, title, body, metadata)
        values (${postId}, ${viewer.userId}, 'bug', 'Request progress', 'Old request shape.', '{"device_model":"private-device"}')
    `;
    const context = { params: Promise.resolve({ postID: postId }) };
    const url = `http://localhost/api/v1/feedback/${postId}`;
    const adminHeaders = { Authorization: `Bearer ${admin.token}`, "Content-Type": "application/json" };
    const viewerHeaders = { Authorization: `Bearer ${viewer.token}`, "Content-Type": "application/json" };
    const command = { expected_status: "submitted", status: "approved", operation_id: randomUUID() };
    assert.equal((await writeStatus(new Request(`${url}/status`, {
        method: "POST", body: JSON.stringify(command),
    }), context)).status, 401);
    assert.equal((await writeStatus(new Request(`${url}/status`, {
        method: "POST", headers: viewerHeaders, body: JSON.stringify(command),
    }), context)).status, 403);
    assert.equal((await sendFix(new Request(`${url}/fix-agent`, {
        method: "POST", headers: viewerHeaders, body: "{}",
    }), context)).status, 403);
    assert.equal((await writeComment(new Request(`${url}/comments`, {
        method: "POST", headers: viewerHeaders, body: JSON.stringify({ body: "Fake approval", workflow_status: "approved" }),
    }), context)).status, 400);
    const ordinary = await writeComment(new Request(`${url}/comments`, {
        method: "POST", headers: viewerHeaders, body: JSON.stringify({ body: "Old client comment", metadata: { device_model: "private-device" } }),
    }), context);
    assert.equal(ordinary.status, 201);
    const ordinaryBody = await ordinary.json();
    assert.deepEqual(ordinaryBody.comment.metadata, {});
    assert.equal(ordinaryBody.comment.workflow_status, undefined);
    assert.equal(ordinaryBody.comment.actor_id, undefined);

    assert.equal((await writeStatus(new Request(`${url}/status`, {
        method: "POST", headers: adminHeaders, body: JSON.stringify(command),
    }), context)).status, 200);
    assert.equal((await sendFix(new Request(`${url}/fix-agent`, {
        method: "POST", headers: adminHeaders, body: "{}",
    }), context)).status, 503);
    assert.equal((await getFeedbackPost(admin.userId, postId, database)).post.workflow_status, "approved");
    process.env.CURSOR_API_KEY = "test-cursor-key-longer-than-32-characters";
    let providerCalls = 0;
    globalThis.fetch = async (input, init) => {
        const target = input instanceof Request ? input.url : String(input);
        if (target === "https://api.cursor.com/v1/agents") {
            providerCalls++;
            assert.doesNotMatch(String(init?.body), /Approved by Marc for build/);
            assert.match(String(init?.body), /Old client comment/);
            return Response.json({ agent: { id: "private-id", url: "https://cursor.com/agents/private-id" } }, { status: 201 });
        }
        return originalFetch(input, init);
    };
    assert.equal((await sendFix(new Request(`${url}/fix-agent`, {
        method: "POST", headers: adminHeaders, body: "{}",
    }), context)).status, 201);
    assert.equal(providerCalls, 1);
    for (const build of [113, 190, 200, 201, 202]) {
        const response = await readDetail(new Request(url, { headers: {
            ...viewerHeaders, "X-FitFight-Version": build >= 201 ? "1.1.1" : "1.0.0", "X-FitFight-Build": String(build),
        } }), context);
        assert.equal(response.status, 200);
        const body = feedbackDetailResponseSchema.parse(await response.json());
        assert.equal(body.post.workflow_status, "building");
        assert.equal(body.can_manage_status, false);
        assert.equal(body.can_launch_fix, false);
        assert.equal(body.comments.length, 3);
        assert.equal(body.post.comment_count, 3);
        assert.ok(body.comments.every((comment) => typeof comment.author_handle === "string"));
        assert.equal(JSON.stringify(body).includes("private-device"), false);
        assert.equal(JSON.stringify(body).includes("private-id"), false);
    }
});
