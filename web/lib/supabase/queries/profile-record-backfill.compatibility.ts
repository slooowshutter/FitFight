import assert from "node:assert/strict";
import { after, test } from "node:test";
import postgres from "postgres";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { profilePageQuerySchema } from "@/lib/types/profiles/shared-profile";
import { readProfileHistory, readSharedProfile } from "./shared-profiles-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 1 });
after(() => database.end());

test("a round accepted before migration counts when it starts and finishes afterward", async () => {
    const owner = "71000000-0000-4000-8000-000000000001";
    const opponent = "71000000-0000-4000-8000-000000000002";
    const fightId = "72000000-0000-4000-8000-000000000004";
    const before = await readSharedProfile(owner, owner, undefined, database);
    assert.equal(before.record?.played, 1);
    assert.equal(before.record.wins, 1);

    await database`update public.fights set state = 'live', starts_at = now() - interval '2 days', ends_at = now() - interval '1 day'
        where id = ${fightId}`;
    await database`update public.fight_members set final_steps_complete = true,
        current_value = case when user_id = ${owner} then 3000 else 1000 end,
        rank = case when user_id = ${owner} then 1 else 2 end where fight_id = ${fightId}`;
    await database`update public.fights set state = 'final' where id = ${fightId}`;

    const afterFinal = await readSharedProfile(owner, owner, undefined, database);
    assert.equal(afterFinal.record?.played, 2);
    assert.equal(afterFinal.record.wins, 2);
    assert.equal(afterFinal.record.categories.private.wins, 1);
    const opponentProfile = await readSharedProfile(opponent, opponent, undefined, database);
    assert.equal(opponentProfile.record?.played, 2);
    assert.equal(opponentProfile.record.wins, 0);
    const history = await readProfileHistory(owner, owner, profilePageQuerySchema.parse({}), database);
    const scheduledResult = history.results.find((row) => row.fight_id === fightId);
    assert.ok(scheduledResult);
    assert.equal(scheduledResult.result, "win");
    assert.equal(scheduledResult.counted, true);
    assert.equal(scheduledResult.field_size, 2);
    assert.equal(history.results.find((row) => row.fight_id === "72000000-0000-4000-8000-000000000002")?.counted, false);
});
