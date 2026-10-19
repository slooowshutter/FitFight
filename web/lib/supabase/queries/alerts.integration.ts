import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { readAlertFacts, recordAlertResponse } from "./alerts-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 3 });
after(() => database.end());

test("alert facts read the account, answered alerts stop counting as new, and responses delete with the account", async (t) => {
    const userId = randomUUID();
    const friendId = randomUUID();
    t.after(async () => {
        await database`delete from auth.users where id in (${userId}, ${friendId})`;
    });
    await database`insert into auth.users (id) values (${userId}), (${friendId})`;

    assert.deepEqual(await readAlertFacts(userId, database), {
        daysSinceSignup: 0,
        fights: 0,
        customCharacters: 0,
        companionPicture: false,
        purchases: 0,
        friends: 0,
        stepsLast7Days: 0,
        answered: new Set(),
    });

    await database`update public.profiles set created_at = now() - interval '4 days' where user_id = ${userId}`;
    const [low, high] = [userId, friendId].sort();
    await database`
        insert into private.profile_friendships (user_low, user_high, requester_id, state, accepted_at)
        values (${low}, ${high}, ${userId}, 'accepted', now())
    `;
    await recordAlertResponse(userId, "start-first-fight", { response: "shown" }, "1.2.0", "300", database);
    let facts = await readAlertFacts(userId, database);
    assert.equal(facts.daysSinceSignup, 4);
    assert.equal(facts.friends, 1);
    assert.deepEqual(facts.answered, new Set(), "Seeing an alert does not answer it");

    await database`update public.profiles set companion_id = 'custom', companion_prompt = 'A fox in a tracksuit' where user_id = ${userId}`;
    assert.equal((await readAlertFacts(userId, database)).companionPicture, false, "A words-only custom animal has no picture");
    await database`update public.profiles set companion_id = 'fox', companion_prompt = null where user_id = ${userId}`;
    assert.equal((await readAlertFacts(userId, database)).companionPicture, true);

    await recordAlertResponse(userId, "start-first-fight", { response: "tapped", action: "new_fight" }, "1.2.0", "300", database);
    await recordAlertResponse(userId, "make-your-character", { response: "dismissed" }, null, null, database);
    facts = await readAlertFacts(userId, database);
    assert.deepEqual(facts.answered, new Set(["start-first-fight", "make-your-character"]));
    assert.deepEqual((await readAlertFacts(friendId, database)).answered, new Set());

    await assert.rejects(
        recordAlertResponse(userId, "Not An Id", { response: "shown" }, null, null, database),
        /check constraint/,
    );
    for (const role of ["anon", "authenticated", "fitfight_backend_reader"]) {
        await assert.rejects(database.begin(async (transaction) => {
            await transaction`set local role ${database(role)}`;
            await transaction`select * from private.alert_responses`;
        }), /permission denied/);
    }

    await database`delete from auth.users where id = ${userId}`;
    const remaining = await database`select id from private.alert_responses where user_id = ${userId}`;
    assert.equal(remaining.length, 0);
});
