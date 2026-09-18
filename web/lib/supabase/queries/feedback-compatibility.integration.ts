import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { createClient } from "@supabase/supabase-js";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { feedbackDetailResponseSchema } from "@/lib/types/feedback/feedback";
import { closeDatabaseClientForTests } from "@/lib/supabase/postgres";
import { GET as readDetail } from "@/app/api/v1/feedback/[postID]/route";
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
    for (let index = 0; index < 2; index++) {
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
    const [admin, viewer] = identities;
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
        ["1.1.1", "201"], ["1.1.1", "202"], ["1.1.2", "203"],
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
});
