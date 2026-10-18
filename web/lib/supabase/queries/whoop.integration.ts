import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { processActivity } from "./activity-pipeline-supabase-query";
import {
    claimWhoopState,
    findWhoopUser,
    readWhoopConnection,
    saveWhoopConnection,
    saveWhoopRecords,
    saveWhoopState,
    withLockedWhoopConnection,
} from "./whoop-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 5 });
after(() => database.end());

const sealed = { ciphertext: "c", iv: "i", tag: "t" };

test("a WHOOP sign-in connects one account, stores raw records, and stays out of the Apple Health resolver", async (t) => {
    const first = randomUUID();
    const second = randomUUID();
    const whoopUserId = Math.floor(Math.random() * 1_000_000_000) + 1;
    t.after(async () => {
        await database`delete from auth.users where id in (${first}, ${second})`;
    });
    await database`insert into auth.users (id) values (${first}), (${second})`;

    await saveWhoopState(first, "Ab12Cd34", database);
    assert.equal(await claimWhoopState("Ab12Cd34", database), first);
    assert.equal(
        await claimWhoopState("Ab12Cd34", database),
        null,
        "a state works once",
    );

    const expiresAt = new Date(Date.now() + 3_600_000);
    await saveWhoopConnection(first, whoopUserId, sealed, expiresAt, database);
    assert.equal(await findWhoopUser(whoopUserId, database), first);

    // The same WHOOP account signing in from another FitFight account moves there.
    await saveWhoopState(second, "Ef56Gh78", database);
    await claimWhoopState("Ef56Gh78", database);
    await saveWhoopConnection(second, whoopUserId, sealed, expiresAt, database);
    assert.equal(await findWhoopUser(whoopUserId, database), second);
    assert.equal(
        (await readWhoopConnection(first, database))?.tokens_ciphertext,
        null,
    );

    const sleep = {
        record_kind: "total" as const,
        record_type: "whoop_sleep",
        record_key: randomUUID(),
        starts_at: "2026-10-17T23:00:00.000Z",
        ends_at: "2026-10-18T07:00:00.000Z",
        time_zone: null,
        payload: { id: "x", score: { sleep_performance_percentage: 91 } },
    };
    await saveWhoopRecords(
        second,
        [sleep],
        { history: true, error: null },
        database,
    );
    await saveWhoopRecords(
        second,
        [sleep],
        { history: false, error: null },
        database,
    );
    const connection = await readWhoopConnection(second, database);
    assert.ok(connection?.last_synced_at && connection.history_synced_at);

    // Pending WHOOP rows must not leave Apple Health uploads reporting "pending".
    assert.equal(
        await processActivity({ userId: second }, database),
        "processed",
    );
    const raw = await database<
        { processing_state: string; provider: string }[]
    >`
        select raw.processing_state, source.provider
        from private.activity_raw as raw
        join public.data_sources as source on source.id = raw.source_id
        where raw.user_id = ${second}
    `;
    assert.deepEqual(
        raw.map((row) => ({ ...row })),
        [{ processing_state: "pending", provider: "whoop" }],
    );

    // WHOOP refusing a refresh forgets the tokens, so the app shows Connect again.
    await withLockedWhoopConnection(
        second,
        async (row, save) => {
            assert.equal(row?.whoop_user_id, whoopUserId);
            await save(null, null);
            return null;
        },
        database,
    );
    assert.equal(await findWhoopUser(whoopUserId, database), null);
});
