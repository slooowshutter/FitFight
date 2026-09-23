import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import {
    readAccountPreferences,
    updateAccountPreferences,
} from "./account-preferences-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 3 });
after(() => database.end());

test("account preferences persist across reads, isolate accounts, merge concurrent fields, and delete with the account", async (t) => {
    const userId = randomUUID();
    const otherId = randomUUID();
    t.after(async () => {
        await database`delete from auth.users where id in (${userId}, ${otherId})`;
    });
    await database`insert into auth.users (id) values (${userId}), (${otherId})`;
    const [profileBefore] = await database`select * from public.profiles where user_id = ${userId}`;
    assert.deepEqual(await readAccountPreferences(userId, database), { language: "system", appearance: "system" });

    await Promise.all([
        updateAccountPreferences(userId, { language: "fr" }, database),
        updateAccountPreferences(userId, { appearance: "dark" }, database),
    ]);
    assert.deepEqual(await readAccountPreferences(userId, database), { language: "fr", appearance: "dark" });
    assert.deepEqual(await readAccountPreferences(otherId, database), { language: "system", appearance: "system" });

    await Promise.all([
        updateAccountPreferences(userId, { language: "en" }, database),
        updateAccountPreferences(userId, { appearance: "light" }, database),
    ]);
    assert.deepEqual(await readAccountPreferences(userId, database), { language: "en", appearance: "light" });
    assert.deepEqual(await updateAccountPreferences(userId, { language: "system" }, database), {
        language: "system", appearance: "light",
    });
    const [profileAfter] = await database`select * from public.profiles where user_id = ${userId}`;
    assert.deepEqual(profileAfter, profileBefore, "Older profile and direct-table contracts stay unchanged");

    await assert.rejects(database`update private.account_preferences set language = 'de' where user_id = ${userId}`, /check constraint/);
    await assert.rejects(database`update private.account_preferences set appearance = 'night' where user_id = ${userId}`, /check constraint/);
    for (const role of ["anon", "authenticated", "fitfight_backend_reader"]) {
        await assert.rejects(database.begin(async (transaction) => {
            await transaction`set local role ${database(role)}`;
            await transaction`select * from private.account_preferences`;
        }), /permission denied/);
    }
    await database`delete from auth.users where id = ${userId}`;
    const remaining = await database`select user_id from private.account_preferences where user_id = ${userId}`;
    assert.equal(remaining.length, 0);
});
