import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import type { AiStepRecord } from "@/lib/types/ai/step";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { claimAzureImageSlot, insertAiStep } from "./ai-steps-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 4 });
after(() => database.end());

test("each Azure region takes drawings up to its per-minute limit, then the next region, then none", async () => {
    const run = randomUUID();
    const regions = [{ name: `test-a-${run}`, perMinute: 2 }, { name: `test-b-${run}`, perMinute: 1 }];
    const claims = await Promise.all(
        Array.from({ length: 4 }, (_, index) => claimAzureImageSlot(regions, run, `step-${index}`, database)),
    );
    const names = [...claims].sort();
    assert.deepEqual(names, [null, regions[0].name, regions[0].name, regions[1].name].sort());

    // A start older than a minute frees its slot.
    await database`update private.ai_image_slots set created_at = now() - interval '61 seconds' where run_id = ${run}`;
    assert.equal(await claimAzureImageSlot(regions, run, "step-later", database), regions[0].name);
});

test("account deletion removes its model logs before run persistence and rejects late callbacks", async (context) => {
    const owner = randomUUID();
    const other = randomUUID();
    const requestId = randomUUID();
    const otherRequestId = randomUUID();
    const runId = randomUUID();
    const otherRunId = randomUUID();
    const fightRunId = randomUUID();
    context.after(async () => {
        await database`delete from private.ai_steps where run_id in (${runId}, ${otherRunId}, ${fightRunId})`;
        await database`delete from auth.users where id in (${owner}, ${other})`;
    });
    await database`insert into auth.users (id) values (${owner}), (${other})`;
    await database`
        insert into private.ai_requests (id, user_id, workflow, idempotency_key, request_hash, workflow_version)
        values (${requestId}, ${owner}, 'avatar', ${randomUUID()}, ${"a".repeat(64)}, '{"workflowId":"fitfight:avatar"}'::jsonb),
            (${otherRequestId}, ${other}, 'avatar', ${randomUUID()}, ${"b".repeat(64)}, '{"workflowId":"fitfight:avatar"}'::jsonb)
    `;
    const step: AiStepRecord = {
        request_id: requestId,
        run_id: runId,
        workflow: "avatar",
        step: "Clean the description",
        step_id: randomUUID(),
        attempt: 1,
        kind: "text",
        provider: "openrouter",
        model: "test-model",
        model_used: null,
        upstream: null,
        status: "completed",
        error: null,
        started_at: new Date(),
        duration_ms: 100,
        first_token_ms: null,
        input_tokens: null,
        output_tokens: null,
        reasoning_tokens: null,
        cached_tokens: null,
        cost_usd: null,
        cost_source: null,
        input: { prompt: "My fox with a green scarf" },
        output: "A fox with a green scarf",
        code_version: "test",
    };
    await insertAiStep(step, database);
    await insertAiStep({ ...step, request_id: otherRequestId, run_id: otherRunId }, database);
    await insertAiStep({ ...step, request_id: null, run_id: fightRunId, workflow: "trail" }, database);
    assert.equal((await database`select run_handle from private.ai_requests where id = ${requestId}`)[0].run_handle, null);
    assert.equal((await database`select count(*)::int as count from private.ai_steps where request_id = ${requestId}`)[0].count, 1);

    await database`delete from auth.users where id = ${owner}`;

    assert.equal((await database`select count(*)::int as count from private.ai_requests where id = ${requestId}`)[0].count, 0);
    assert.equal((await database`select count(*)::int as count from private.ai_steps where run_id = ${runId}`)[0].count, 0);
    const remaining = await database`
        select run_id, request_id from private.ai_steps where run_id in (${otherRunId}, ${fightRunId}) order by run_id
    `;
    assert.deepEqual(remaining.map((row) => ({ run_id: row.run_id, request_id: row.request_id })), [
        { run_id: otherRunId, request_id: otherRequestId },
        { run_id: fightRunId, request_id: null },
    ].sort((left, right) => left.run_id.localeCompare(right.run_id)));
    await assert.rejects(insertAiStep({ ...step, step_id: randomUUID(), attempt: 2 }, database), { code: "23503" });
    await assert.rejects(insertAiStep({ ...step, request_id: null, step_id: randomUUID() }, database), { code: "23514" });
    assert.equal((await database`select count(*)::int as count from private.ai_steps where run_id = ${runId}`)[0].count, 0);
});
