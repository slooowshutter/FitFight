import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test, type TestContext } from "node:test";
import postgres from "postgres";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { readCustomCharacterStore } from "./custom-characters-supabase-query";
import {
    claimFreeSpecial,
    grantReferralFreeCharacters,
    readFreeCharacters,
    readReferralGrants,
} from "./free-characters-supabase-query";
import { claimReferral } from "./referrals-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
process.env.APPLE_IAP_ENVIRONMENT = "Sandbox";
const database = postgres(env.DATABASE_URL, { max: 5 });
after(() => database.end());

async function accounts(context: TestContext, count: number) {
    const users = Array.from({ length: count }, () => randomUUID());
    for (const userId of users) await database`insert into auth.users (id) values (${userId})`;
    context.after(async () => {
        await database`delete from private.special_purchases where account_id in (
            select id from private.special_accounts where user_id = any(${database.array(users)}::uuid[]))`;
        await database`delete from private.special_accounts where user_id = any(${database.array(users)}::uuid[])`;
        await database`delete from auth.users where id = any(${database.array(users)}::uuid[])`;
    });
    return users;
}

async function referralCode(userId: string) {
    const [row] = await database`select referral_code from public.profiles where id = ${userId}`;
    return { code: row.referral_code as string };
}

async function stepsDay(userId: string, provider: string, value: number, day = "2026-10-14") {
    const [source] = await database`insert into public.data_sources (user_id, provider, source_label, connection_route)
        values (${userId}, ${provider}, ${provider}, 'healthkit')
        on conflict (user_id, provider, connection_route) do update set updated_at = now() returning id`;
    await database`insert into private.activity_metrics (user_id, source_id, scope, scope_key, metric, starts_at, ends_at,
            observed_through, day, value, unit, input_ids, calculation_version)
        values (${userId}, ${source.id}, 'day', ${day}, 'steps', ${day}::date, ${day}::date + 1, ${day}::date + 1,
            ${day}::date, ${value}, 'count', array[gen_random_uuid()], 1)`;
}

test("only an account created at most 7 days ago can be referred", async (context) => {
    const [referrer, fresh, old] = await accounts(context, 3);
    await database`update public.profiles set created_at = now() - interval '8 days' where id = ${old}`;
    assert.deepEqual(await claimReferral(old, await referralCode(referrer), database), {
        recorded: false,
        account_not_new: true,
    });
    await database`update public.profiles set created_at = now() - interval '7 days' + interval '1 minute' where id = ${fresh}`;
    assert.deepEqual(await claimReferral(fresh, await referralCode(referrer), database), {
        recorded: true,
        account_not_new: false,
    });
    assert.equal((await database`select 1 from private.referrals where referred_user_id = ${old}`).length, 0);
});

test("a referral pays the referrer and the friend once, when the friend's Apple Health steps arrive", async (context) => {
    const [referrer, friend, stranger] = await accounts(context, 3);
    const handle = `friend_${randomUUID().slice(0, 8)}`;
    assert.equal((await readCustomCharacterStore(friend, database)).free_characters, 0);
    assert.equal((await readCustomCharacterStore(friend, database)).referral_pending, false);

    // Steps alone pay nothing; neither does a referral before any Apple Health steps.
    await stepsDay(stranger, "apple_health", 4000);
    assert.deepEqual(await grantReferralFreeCharacters(stranger, database), []);
    assert.equal((await claimReferral(friend, await referralCode(referrer), database)).recorded, true);
    assert.equal((await readCustomCharacterStore(friend, database)).referral_pending, true);
    await stepsDay(friend, "apple_health", 0, "2026-10-13");
    await stepsDay(friend, "whoop", 9000);
    assert.deepEqual(await grantReferralFreeCharacters(friend, database), []);
    assert.equal(await readFreeCharacters(database, referrer), 0);

    await stepsDay(friend, "apple_health", 3200);
    const [first, replay] = await Promise.all([
        grantReferralFreeCharacters(friend, database),
        grantReferralFreeCharacters(friend, database),
    ]);
    assert.deepEqual([...first, ...replay], [{ referrer_id: referrer, friend_handle: null, notify: true }]);
    assert.deepEqual(await grantReferralFreeCharacters(null, database), []);
    assert.equal(await readFreeCharacters(database, referrer), 1);
    assert.equal(await readFreeCharacters(database, friend), 1);
    assert.equal(await readFreeCharacters(database, stranger), 0);
    const store = await readCustomCharacterStore(friend, database);
    assert.equal(store.free_characters, 1);
    assert.equal(store.referral_pending, false);
    const grants = await database`select user_id, reason, granted_by, operation_key from private.free_character_grants
        where operation_key = ${friend} order by reason`;
    assert.deepEqual(grants.map((row) => ({ ...row })), [
        { user_id: referrer, reason: "referral", granted_by: friend, operation_key: friend },
        { user_id: friend, reason: "referred", granted_by: referrer, operation_key: friend },
    ]);

    await database`update public.profiles set handle = ${handle}, handle_set_at = now() where id = ${friend}`;
    const listed = await readReferralGrants(database);
    assert.ok(listed.total >= 1);
    assert.equal(listed.grants.find((grant) => grant.friend === handle)?.referrer !== undefined, true);
});

test("the sweep pays a referral whose steps arrived first, names the friend and skips muted referrers", async (context) => {
    const [referrer, friend, deletedReferrer, orphan, veteran] = await accounts(context, 5);
    const handle = `walker_${randomUUID().slice(0, 8)}`;
    await database`update public.profiles set handle = ${handle}, handle_set_at = now() where id = ${friend}`;
    await database`insert into private.notification_preferences (user_id, enabled) values (${referrer}, false)`;
    await stepsDay(friend, "apple_health", 5000);
    await stepsDay(orphan, "apple_health", 5000);
    await stepsDay(veteran, "apple_health", 5000);
    // Recorded before the program started, by a backend without the 7-day rule.
    await database`insert into private.referrals (referred_user_id, referrer_user_id, created_at)
        values (${veteran}, ${referrer}, '2026-09-20T12:00:00Z')`;
    assert.equal((await claimReferral(friend, await referralCode(referrer), database)).recorded, true);
    assert.equal((await claimReferral(orphan, await referralCode(deletedReferrer), database)).recorded, true);
    await database`update public.profiles set deleted_at = now() where id = ${deletedReferrer}`;

    const paid = await grantReferralFreeCharacters(null, database);
    assert.deepEqual(paid.filter((payout) => payout.referrer_id === referrer || payout.referrer_id === deletedReferrer), [
        { referrer_id: referrer, friend_handle: handle, notify: false },
    ]);
    assert.equal(await readFreeCharacters(database, friend), 1);
    assert.equal(await readFreeCharacters(database, orphan), 0);
    assert.equal(await readFreeCharacters(database, veteran), 0);
    assert.equal((await readCustomCharacterStore(orphan, database)).referral_pending, false);
});

test("a free character unlocks one Special, once per key, and the Special can then be worn", async (context) => {
    const [owner, other] = await accounts(context, 2);
    await assert.rejects(claimFreeSpecial(owner, randomUUID(), "limited-tiger", database), { code: "no_free_characters" });
    await database`insert into private.free_character_grants (user_id, quantity, reason, operation_key)
        values (${owner}, 1, 'gift', ${randomUUID()})`;

    const key = randomUUID();
    const claim = await claimFreeSpecial(owner, key, "limited-tiger", database);
    assert.deepEqual(claim, { outcome: "owned", transaction_id: key, companion_id: "limited-tiger" });
    assert.deepEqual(await claimFreeSpecial(owner, key, "limited-tiger", database), claim);
    await assert.rejects(claimFreeSpecial(other, key, "limited-tiger", database), { code: "ai_request_conflict" });
    assert.equal(await readFreeCharacters(database, owner), 0);
    // Already owned: nothing is spent even with no free character left.
    assert.equal((await claimFreeSpecial(owner, randomUUID(), "limited-tiger", database)).outcome, "owned");
    await assert.rejects(claimFreeSpecial(owner, randomUUID(), "limited-cheetah", database), { code: "no_free_characters" });

    await database`update public.profiles set companion_id = 'limited-tiger' where id = ${owner}`;
    const [account] = await database`select id from private.special_accounts where user_id = ${owner}`;
    await assert.rejects(database`insert into private.special_purchases (account_id, environment, companion_id)
        values (${account.id}, 'Sandbox', 'limited-tiger')`, { code: "23514" });
});

test("taken_back grants are negative and count against the remaining free characters", async (context) => {
    const [owner] = await accounts(context, 1);
    await database`insert into private.free_character_grants (user_id, quantity, reason, operation_key) values
        (${owner}, 2, 'gift', ${randomUUID()}), (${owner}, -2, 'taken_back', ${randomUUID()})`;
    assert.equal(await readFreeCharacters(database, owner), 0);
    await assert.rejects(database`insert into private.free_character_grants (user_id, quantity, reason, operation_key)
        values (${owner}, -1, 'gift', ${randomUUID()})`, { code: "23514" });
});
