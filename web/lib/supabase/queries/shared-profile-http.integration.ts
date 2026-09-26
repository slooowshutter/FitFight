import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";
import { GET as readMe, PATCH as updateMe } from "@/app/api/v1/me/route";
import { GET as readProfile } from "@/app/api/v1/profiles/[userID]/route";
import { PATCH as updateSettings } from "@/app/api/v1/me/profile-settings/route";
import { POST as requestFriend } from "@/app/api/v1/friends/[userID]/request/route";
import { POST as respondFriend } from "@/app/api/v1/friends/[userID]/respond/route";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { sharedProfileSchema } from "@/lib/types/profiles/shared-profile";
import { profileSchema } from "@/lib/types/profiles/profile";
import { readSpecialStore, recordSpecialTransaction } from "./specials-supabase-query";
import { appleSpecialTransactionSchema } from "@/lib/types/apple/special-purchase";
import { closeDatabaseClientForTests } from "@/lib/supabase/postgres";

const env = databaseTestEnvironmentSchema.parse(process.env);
process.env.NEXT_PUBLIC_SUPABASE_URL = env.SUPABASE_TEST_URL;
process.env.SUPABASE_SECRET_KEY = env.SUPABASE_TEST_SERVICE_KEY;
process.env.APPLE_IAP_ENVIRONMENT = "Sandbox";
process.env.APPLE_SPECIALS_ENABLED = "true";
const database = postgres(env.DATABASE_URL, { max: 2 });
const admin = createClient(env.SUPABASE_TEST_URL, env.SUPABASE_TEST_SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
after(async () => { await closeDatabaseClientForTests(); await database.end(); });

test("authenticated legacy /me and new mutual-profile contracts coexist before and after the later grant cutoff", async (t) => {
    const sessions = [];
    for (let index = 0; index < 2; index++) {
        const email = `shared-profile-${randomUUID()}@example.com`;
        const password = randomUUID();
        const created = await admin.auth.admin.createUser({ email, password, email_confirm: true });
        assert.equal(created.error, null);
        assert.ok(created.data.user);
        const userId = created.data.user.id;
        t.after(async () => { await database`delete from auth.users where id = ${userId}`; });
        const client = createClient(env.SUPABASE_TEST_URL, env.SUPABASE_TEST_ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
        const signedIn = await client.auth.signInWithPassword({ email, password });
        assert.equal(signedIn.error, null);
        assert.ok(signedIn.data.session);
        sessions.push({ userId, token: signedIn.data.session.access_token });
    }
    const [viewer, target] = sessions;
    const context = { params: Promise.resolve({ userID: target.userId }) };
    const headers = { authorization: `Bearer ${viewer.token}`, "content-type": "application/json" };
    const unsetProfile = await readMe(new Request("https://staging.fitfight.app/api/v1/me", { headers }), { params: Promise.resolve({}) });
    assert.equal(unsetProfile.status, 200);
    assert.equal(profileSchema.parse(await unsetProfile.json()).time_zone, "UTC");
    const zoneResponse = await updateMe(new Request("https://staging.fitfight.app/api/v1/me", {
        method: "PATCH", headers, body: JSON.stringify({ time_zone: "Pacific/Kiritimati" }),
    }), { params: Promise.resolve({}) });
    assert.equal(zoneResponse.status, 200);
    assert.equal(profileSchema.parse(await zoneResponse.json()).time_zone, "Pacific/Kiritimati");
    const unpaidSave = await updateMe(new Request("https://staging.fitfight.app/api/v1/me", {
        method: "PATCH", headers, body: JSON.stringify({ companion_id: "limited-pangolin" }),
    }), { params: Promise.resolve({}) });
    assert.equal(unpaidSave.status, 403);
    const store = await readSpecialStore(viewer.userId, database);
    t.after(async () => {
        await database`delete from private.special_transactions where account_id = ${store.app_account_token}`;
        await database`update private.special_editions set state = 'available', account_id = null, original_transaction_id = null, attempt_id = null where account_id = ${store.app_account_token}`;
        await database`delete from private.special_accounts where id = ${store.app_account_token}`;
    });
    await recordSpecialTransaction(appleSpecialTransactionSchema.parse({
        transactionId: "200000099", originalTransactionId: "200000099",
        bundleId: "com.fitfight.mvp", productId: "com.fitfight.mvp.special.pangolin",
        environment: "Sandbox", type: "Non-Consumable", inAppOwnershipType: "PURCHASED", quantity: 1,
        appAccountToken: store.app_account_token, purchaseDate: 1_790_000_000_000, signedDate: 1_790_000_001_000,
    }), database);
    const limitedSave = await updateMe(new Request("https://staging.fitfight.app/api/v1/me", {
        method: "PATCH", headers, body: JSON.stringify({ companion_id: "limited-pangolin" }),
    }), { params: Promise.resolve({}) });
    assert.equal(limitedSave.status, 200);
    for (const [version, build] of [["1.0.0", "113"], ["1.0.0", "190"], ["1.1.0", "200"], ["1.1.1", "201"], ["1.1.1", "202"], ["1.1.2", "203"], ["1.1.2", "204"], ["1.1.2", "205"]]) {
        const response = await readMe(new Request("https://staging.fitfight.app/api/v1/me", {
            headers: { ...headers, "X-FitFight-Version": version, "X-FitFight-Build": build },
        }), { params: Promise.resolve({}) });
        assert.equal(response.status, 200);
        const payload = await response.json();
        assert.deepEqual(Object.keys(payload).sort(), [
            "user_id", "handle", "display_name", "handle_set_at", "referral_code", "avatar",
            "companion_id", "companion_prompt", "time_zone",
        ].sort(), "Storage IDs and row timestamps must not leak into the v1 profile contract");
        const profile = profileSchema.parse(payload);
        assert.equal(profile.user_id, viewer.userId);
        assert.ok(profile.referral_code);
        assert.equal(profile.time_zone, "Pacific/Kiritimati");
        assert.equal(profile.companion_id, "limited-pangolin");
        const legacyPatch = await updateMe(new Request("https://staging.fitfight.app/api/v1/me", {
            method: "PATCH",
            headers: { ...headers, "X-FitFight-Version": version, "X-FitFight-Build": build },
            body: JSON.stringify({ display_name: "Updated by an older app" }),
        }), { params: Promise.resolve({}) });
        assert.equal(legacyPatch.status, 200);
        assert.equal(profileSchema.parse(await legacyPatch.json()).time_zone, "Pacific/Kiritimati", "Omitted zones remain unchanged");
    }
    const releaseEdition = await updateMe(new Request("https://staging.fitfight.app/api/v1/me", {
        method: "PATCH", headers, body: JSON.stringify({ companion_id: "fox", companion_prompt: null }),
    }), { params: Promise.resolve({}) });
    assert.equal(releaseEdition.status, 200, "Older stock selection requests remain valid");
    const request = new Request(`https://staging.fitfight.app/api/v1/profiles/${target.userId}`, { headers });
    const initial = await readProfile(request, context);
    assert.equal(initial.status, 200);
    assert.equal(initial.headers.get("cache-control"), "no-store");
    assert.equal(sharedProfileSchema.parse(await initial.json()).access, "private");
    const updated = await updateSettings(new Request("https://staging.fitfight.app/api/v1/me/profile-settings", {
        method: "PATCH", headers: { ...headers, authorization: `Bearer ${target.token}` }, body: JSON.stringify({ competitive: true }),
    }), { params: Promise.resolve({}) });
    assert.equal(updated.status, 200);
    assert.equal((await requestFriend(new Request(`https://staging.fitfight.app/api/v1/friends/${target.userId}/request`, { method: "POST", headers }), context)).status, 200);
    const denied = await respondFriend(new Request(`https://staging.fitfight.app/api/v1/friends/${target.userId}/respond`, {
        method: "POST", headers, body: JSON.stringify({ action: "accept" }),
    }), context);
    assert.equal(denied.status, 403);
    const accepted = await respondFriend(new Request(`https://staging.fitfight.app/api/v1/friends/${viewer.userId}/respond`, {
        method: "POST", headers: { ...headers, authorization: `Bearer ${target.token}` }, body: JSON.stringify({ action: "accept" }),
    }), { params: Promise.resolve({ userID: viewer.userId }) });
    assert.equal(accepted.status, 200);
    const visible = sharedProfileSchema.parse(await (await readProfile(request, context)).json());
    assert.equal(visible.friendship, "friends");
    assert.equal(visible.record?.played, 0);
    assert.equal("referral_code" in visible.identity, false);
    assert.equal("companion_prompt" in visible.identity, false);
});
