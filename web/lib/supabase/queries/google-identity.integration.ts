import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { createClient } from "@supabase/supabase-js";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { closeDatabaseClientForTests } from "@/lib/supabase/postgres";
import { reconcileGoogleIdentity } from "./google-identity-supabase-query";
import type { GoogleIdTokenClaims } from "@/lib/types/auth/google-sign-in";

const env = databaseTestEnvironmentSchema.parse(process.env);
process.env.NEXT_PUBLIC_SUPABASE_URL = env.SUPABASE_TEST_URL;
process.env.SUPABASE_SECRET_KEY = env.SUPABASE_TEST_SERVICE_KEY;
const database = postgres(env.DATABASE_URL, { max: 2 });
const admin = createClient(env.SUPABASE_TEST_URL, env.SUPABASE_TEST_SERVICE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
});
after(() => database.end());
after(() => closeDatabaseClientForTests());

test("Google tokens attach to an existing Apple account with the same verified email", async (t) => {
    const email = `google-link-${randomUUID()}@example.com`;
    const apple = await admin.auth.admin.createUser({
        email,
        email_confirm: true,
        app_metadata: { provider: "apple", providers: ["apple"] },
    });
    assert.equal(apple.error, null);
    assert.ok(apple.data.user);
    const appleId = apple.data.user.id;
    const subject = `google-sub-${randomUUID()}`;
    t.after(async () => {
        await database`delete from auth.users where id = ${appleId}`;
    });
    await database`
        insert into auth.identities (
            id, user_id, identity_data, provider, provider_id,
            last_sign_in_at, created_at, updated_at
        ) values (
            ${randomUUID()},
            ${appleId},
            ${database.json({ sub: appleId, email, email_verified: true })},
            'apple',
            ${appleId},
            now(), now(), now()
        )
    `;
    await database`
        update auth.users
        set email = null, email_confirmed_at = null
        where id = ${appleId}
    `;
    await database`update public.profiles set handle = ${"gl_" + appleId.slice(0, 8)}, handle_set_at = now() where user_id = ${appleId}`;

    const google = await admin.auth.admin.createUser({
        email: `other-${randomUUID()}@example.com`,
        email_confirm: true,
        app_metadata: { provider: "google", providers: ["google"] },
    });
    assert.equal(google.error, null);
    assert.ok(google.data.user);
    const createdGoogleId = google.data.user.id;
    t.after(async () => {
        await database`delete from auth.users where id = ${createdGoogleId}`;
    });
    await database`delete from auth.identities where user_id = ${createdGoogleId}`;
    await database`
        update auth.users
        set email = null, email_confirmed_at = null
        where id = ${createdGoogleId}
    `;
    await database`
        insert into auth.identities (
            id, user_id, identity_data, provider, provider_id,
            last_sign_in_at, created_at, updated_at
        ) values (
            ${randomUUID()},
            ${createdGoogleId},
            ${database.json({ sub: subject, email, email_verified: true })},
            'google',
            ${subject},
            now(), now(), now()
        )
    `;

    const claims: GoogleIdTokenClaims = {
        aud: "428975685987-i4dlh5lj59foo21p40pvmmnea5glipac.apps.googleusercontent.com",
        email,
        email_verified: true,
        exp: Math.floor(Date.now() / 1000) + 300,
        iss: "https://accounts.google.com",
        sub: subject,
    };
    const result = await reconcileGoogleIdentity(
        {
            idToken: "unused",
            accessToken: "google-access-token",
            nonce: "abcDEF0123456789-_xyzXYZ01234567",
        },
        {
            database,
            verify: async () => claims,
        },
    );
    assert.deepEqual(result, { linked: true });
    const identities = await database<{ provider: string; user_id: string }[]>`
        select provider, user_id from auth.identities
        where provider_id = ${subject} and provider = 'google'
    `;
    assert.equal(identities.length, 1);
    assert.deepEqual(identities[0], { provider: "google", user_id: appleId });
    const leftover = await database<{ count: number }[]>`
        select count(*)::integer as count from auth.users where id = ${createdGoogleId}
    `;
    assert.equal(leftover[0]?.count, 0);
});
