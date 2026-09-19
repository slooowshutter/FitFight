import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { createClient } from "@supabase/supabase-js";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { feedbackArchiveResponseSchema, feedbackDetailResponseSchema, feedbackListResponseSchema } from "@/lib/types/feedback/feedback";
import { closeDatabaseClientForTests } from "@/lib/supabase/postgres";
import { GET as readDetail, DELETE as deletePost, PATCH as archivePost } from "@/app/api/v1/feedback/[postID]/route";
import { GET as readList } from "@/app/api/v1/feedback/route";
import { POST as votePost } from "@/app/api/v1/feedback/[postID]/vote/route";
import { POST as writeComment } from "@/app/api/v1/feedback/[postID]/comments/route";
import { POST as sendFix } from "@/app/api/v1/feedback/[postID]/fix-agent/route";
import { getFeedbackPost, listFeedbackPosts, toggleFeedbackVote } from "./feedback-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
process.env.NEXT_PUBLIC_SUPABASE_URL = env.SUPABASE_TEST_URL;
process.env.SUPABASE_SECRET_KEY = env.SUPABASE_TEST_SERVICE_KEY;
const database = postgres(env.DATABASE_URL, { max: 4 });
after(() => database.end());
after(() => closeDatabaseClientForTests());

test("ordinary feedback, Profile links, votes, and explicit Send preserve supported clients", async (t) => {
    const auth = createClient(env.SUPABASE_TEST_URL, env.SUPABASE_TEST_SERVICE_KEY, {
        auth: { persistSession: false, autoRefreshToken: false },
    });
    const identities: { userId: string; token: string }[] = [];
    const previous = {
        FITFIGHT_ADMIN_HANDLES: process.env.FITFIGHT_ADMIN_HANDLES,
        CURSOR_API_KEY: process.env.CURSOR_API_KEY,
        NOTION_TOKEN: process.env.NOTION_TOKEN,
    };
    const originalFetch = globalThis.fetch;
    t.after(async () => {
        globalThis.fetch = originalFetch;
        for (const [name, value] of Object.entries(previous)) {
            if (value === undefined) delete process.env[name];
            else process.env[name] = value;
        }
        if (identities.length) {
            await database`delete from auth.users where id in ${database(identities.map((identity) => identity.userId))}`;
        }
    });
    for (let index = 0; index < 3; index++) {
        const email = `feedback-${randomUUID()}@example.com`;
        const password = randomUUID();
        const created = await auth.auth.admin.createUser({ email, password, email_confirm: true });
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
    const [admin, viewer, other] = identities;
    const adminHandle = `fb_${admin.userId.slice(0, 8)}`;
    await database`update public.profiles set handle = ${adminHandle} where user_id = ${admin.userId}`;
    process.env.FITFIGHT_ADMIN_HANDLES = adminHandle;
    delete process.env.CURSOR_API_KEY;
    delete process.env.NOTION_TOKEN;
    const postId = randomUUID();
    await database`
        insert into public.feedback_posts (id, author_id, kind, title, body, metadata)
        values (${postId}, ${viewer.userId}, 'bug', 'Steps chart', 'Old request shape.', '{"device_model":"private-device"}')
    `;
    const context = { params: Promise.resolve({ postID: postId }) };
    const url = `http://localhost/api/v1/feedback/${postId}`;
    const adminHeaders = { Authorization: `Bearer ${admin.token}`, "Content-Type": "application/json" };
    const viewerHeaders = { Authorization: `Bearer ${viewer.token}`, "Content-Type": "application/json" };
    assert.equal((await readDetail(new Request(url), context)).status, 401);
    assert.equal((await sendFix(new Request(`${url}/fix-agent`, {
        method: "POST", headers: viewerHeaders, body: "{}",
    }), context)).status, 403);
    const ordinary = await writeComment(new Request(`${url}/comments`, {
        method: "POST", headers: viewerHeaders,
        body: JSON.stringify({ body: "Old client comment", metadata: { device_model: "private-device" } }),
    }), context);
    assert.equal(ordinary.status, 201);
    assert.deepEqual(await toggleFeedbackVote(admin.userId, postId, database), { voted: true, vote_count: 1 });
    assert.equal((await listFeedbackPosts(viewer.userId, {}, database)).posts.find((post) => post.id === postId)?.vote_count, 1);

    assert.equal((await sendFix(new Request(`${url}/fix-agent`, {
        method: "POST", headers: adminHeaders, body: "{}",
    }), context)).status, 503);
    const beforeSend = await getFeedbackPost(admin.userId, postId, database);
    process.env.CURSOR_API_KEY = "test-cursor-key-longer-than-32-characters";
    let providerCalls = 0;
    globalThis.fetch = async (input, init) => {
        const target = input instanceof Request ? input.url : String(input);
        if (target === "https://api.cursor.com/v1/agents") {
            providerCalls++;
            assert.match(String(init?.body), /Old client comment/);
            return Response.json({ agent: { id: "private-id", url: "https://cursor.com/agents/private-id" } }, { status: 201 });
        }
        return originalFetch(input, init);
    };
    assert.equal((await sendFix(new Request(`${url}/fix-agent`, {
        method: "POST", headers: adminHeaders, body: "{}",
    }), context)).status, 201);
    assert.equal(providerCalls, 1);
    assert.deepEqual(await getFeedbackPost(admin.userId, postId, database), beforeSend);

    for (const [version, build] of [
        ["1.0.0", "113"], ["1.0.0", "190"], ["1.1.0", "200"],
        ["1.1.1", "201"], ["1.1.1", "202"], ["1.1.2", "203"], ["1.1.2", "204"],
    ]) {
        const response = await readDetail(new Request(url, { headers: {
            ...viewerHeaders, "X-FitFight-Version": version, "X-FitFight-Build": build,
        } }), context);
        assert.equal(response.status, 200);
        const body = feedbackDetailResponseSchema.parse(await response.json());
        assert.equal(body.can_launch_fix, false);
        assert.equal(body.comments.length, 1);
        assert.equal(body.post.comment_count, 1);
        assert.equal(body.comments[0].author_id, viewer.userId);
        assert.equal(body.comments[0].body, "Old client comment");
        assert.equal(JSON.stringify(body).includes("private-device"), false);
        assert.equal(JSON.stringify(body).includes("private-id"), false);
    }

    await t.test("author deletion and admin archival use authenticated HTTP commands", async () => {
        const otherHeaders = { Authorization: `Bearer ${other.token}`, "Content-Type": "application/json" };
        const changed = { method: "PATCH", body: JSON.stringify({ archived: true, reason: "Resolved" }) };
        assert.equal((await archivePost(new Request(url, changed), context)).status, 401);
        assert.equal((await archivePost(new Request(url, { ...changed, headers: viewerHeaders }), context)).status, 403);
        assert.equal((await deletePost(new Request(url, { method: "DELETE", headers: otherHeaders }), context)).status, 403);
        assert.equal((await archivePost(new Request(url, { ...changed, headers: adminHeaders, body: '{"archived":"yes"}' }), context)).status, 400);
        assert.equal((await archivePost(new Request(url, { ...changed, headers: adminHeaders, body: JSON.stringify({ archived: true, reason: "x".repeat(281) }) }), context)).status, 400);
        const archived = await archivePost(new Request(url, { ...changed, headers: adminHeaders }), context);
        assert.equal(archived.status, 200);
        assert.deepEqual(feedbackArchiveResponseSchema.parse(await archived.json()), { archived: true, archive_reason: "Resolved" });
        const listURL = "http://localhost/api/v1/feedback";
        const open = feedbackListResponseSchema.parse(await (await readList(new Request(listURL, { headers: viewerHeaders }), { params: Promise.resolve({}) })).json());
        assert.equal(open.posts.some((post) => post.id === postId), false);
        const history = feedbackListResponseSchema.parse(await (await readList(new Request(`${listURL}?status=archived`, { headers: viewerHeaders }), { params: Promise.resolve({}) })).json());
        assert.equal(history.posts.find((post) => post.id === postId)?.vote_count, 1);
        assert.equal(history.posts.find((post) => post.id === postId)?.comment_count, 1);
        assert.equal(history.can_archive, false);
        const detail = feedbackDetailResponseSchema.parse(await (await readDetail(new Request(url, { headers: viewerHeaders }), context)).json());
        assert.equal(detail.can_delete, true);
        assert.equal(detail.can_archive, false);
        assert.equal(detail.post.archive_reason, "Resolved");
        assert.equal(detail.comments.length, 1);
        for (const build of ["113", "190", "200", "201", "202", "203", "204"]) {
            const headers = { ...viewerHeaders, "X-FitFight-Build": build, "X-FitFight-Version": "1.1.2" };
            assert.equal((await votePost(new Request(`${url}/vote`, { method: "POST", headers }), context)).status, 409);
            assert.equal((await writeComment(new Request(`${url}/comments`, {
                method: "POST", headers, body: JSON.stringify({ body: "Late comment" }),
            }), context)).status, 409);
        }
        const kept = await getFeedbackPost(admin.userId, postId, database);
        assert.equal(kept.post.vote_count, 1);
        assert.equal(kept.comments.length, 1);
        assert.equal((await archivePost(new Request(url, {
            method: "PATCH", headers: adminHeaders, body: '{"archived":false}',
        }), context)).status, 200);
        const reopened = await getFeedbackPost(viewer.userId, postId, database);
        assert.equal(reopened.post.archived, false);
        assert.equal(reopened.post.archive_reason, null);
        assert.equal(reopened.comments.length, 1);
        assert.equal((await votePost(new Request(`${url}/vote`, { method: "POST", headers: viewerHeaders }), context)).status, 200);
        assert.equal((await writeComment(new Request(`${url}/comments`, {
            method: "POST", headers: viewerHeaders, body: '{"body":"After reopening"}',
        }), context)).status, 201);
        await archivePost(new Request(url, { ...changed, headers: adminHeaders }), context);
        assert.equal((await deletePost(new Request(url, { method: "DELETE", headers: viewerHeaders }), context)).status, 200);
        const [counts] = await database`
            select (select count(*)::int from public.feedback_posts where id = ${postId}) as posts,
                (select count(*)::int from public.feedback_comments where post_id = ${postId}) as comments,
                (select count(*)::int from public.feedback_votes where post_id = ${postId}) as votes
        `;
        assert.deepEqual(counts, { posts: 0, comments: 0, votes: 0 });
        assert.equal((await archivePost(new Request(url, { ...changed, headers: adminHeaders }), context)).status, 404);
    });

    await t.test("votes and comments wait for a concurrent archive and then respect it", async () => {
        const concurrentId = randomUUID();
        await database`insert into public.feedback_posts (id, author_id, kind, title, body)
            values (${concurrentId}, ${viewer.userId}, 'bug', 'Concurrent post', 'Keep the discussion')`;
        const concurrentURL = `http://localhost/api/v1/feedback/${concurrentId}`;
        const concurrentContext = { params: Promise.resolve({ postID: concurrentId }) };
        const pending: Promise<Response>[] = [];
        await database.begin("read write", async (sql) => {
            await sql`update public.feedback_posts set archived = true where id = ${concurrentId}`;
            pending.push(votePost(new Request(`${concurrentURL}/vote`, { method: "POST", headers: viewerHeaders }), concurrentContext));
            pending.push(writeComment(new Request(`${concurrentURL}/comments`, {
                method: "POST", headers: viewerHeaders, body: '{"body":"Concurrent comment"}',
            }), concurrentContext));
            let waiting = 0;
            for (let attempt = 0; attempt < 300 && waiting < 2; attempt++) {
                const [activity] = await database<{ waiting: number }[]>`
                    select count(*)::int as waiting from pg_stat_activity
                    where wait_event_type = 'Lock' and query like '%select archived, archive_reason from public.feedback_posts%'
                `;
                waiting = activity.waiting;
                if (waiting < 2) await new Promise((resolve) => setTimeout(resolve, 20));
            }
            assert.equal(waiting, 2, "both commands must lock the post before deciding whether it is writable");
        });
        const responses = await Promise.all(pending);
        assert.deepEqual(responses.map((response) => response.status), [409, 409]);
        const detail = await getFeedbackPost(viewer.userId, concurrentId, database);
        assert.equal(detail.post.vote_count, 0);
        assert.equal(detail.post.comment_count, 0);
        await deletePost(new Request(concurrentURL, { method: "DELETE", headers: adminHeaders }), concurrentContext);
    });

    await t.test("default list includes both types, type filters work, and date order is selectable", async () => {
        const featureId = randomUUID();
        const bugId = randomUUID();
        await database`
            insert into public.feedback_posts (id, author_id, kind, title, body, created_at)
            values (${featureId}, ${viewer.userId}, 'feature', 'Older popular feature', 'Feature body', '2026-01-01'),
                (${bugId}, ${viewer.userId}, 'bug', 'Recent bug', 'Bug body', '2026-02-01')
        `;
        await database`insert into public.feedback_votes (post_id, user_id) values (${featureId}, ${admin.userId})`;
        const listURL = "http://localhost/api/v1/feedback";
        const defaultResponse = await readList(new Request(listURL, { headers: viewerHeaders }), { params: Promise.resolve({}) });
        assert.equal(defaultResponse.status, 200);
        const defaults = feedbackListResponseSchema.parse(await defaultResponse.json()).posts.filter((post) => (post.id === featureId || post.id === bugId));
        assert.deepEqual(defaults.map((post) => post.id), [featureId, bugId]);
        for (const [sort, ids] of [["newest", [bugId, featureId]], ["oldest", [featureId, bugId]]] as const) {
            const result = await listFeedbackPosts(viewer.userId, { sort }, database);
            assert.deepEqual(result.posts.filter((post) => (post.id === featureId || post.id === bugId)).map((post) => post.id), ids);
        }
        const bugs = await listFeedbackPosts(viewer.userId, { kind: "bug" }, database);
        assert.ok(bugs.posts.some((post) => post.id === bugId));
        assert.equal(bugs.posts.some((post) => post.id === featureId), false);
        for (const query of ["status=invalid", "sort=random", "kind=all"]) {
            assert.equal((await readList(new Request(`${listURL}?${query}`, { headers: viewerHeaders }), { params: Promise.resolve({}) })).status, 400);
        }
        const featureContext = { params: Promise.resolve({ postID: featureId }) };
        assert.equal((await deletePost(new Request(`${listURL}/${featureId}`, { method: "DELETE", headers: adminHeaders }), featureContext)).status, 200);
        const bugContext = { params: Promise.resolve({ postID: bugId }) };
        assert.equal((await deletePost(new Request(`${listURL}/${bugId}`, { method: "DELETE", headers: viewerHeaders }), bugContext)).status, 200);
    });

});
