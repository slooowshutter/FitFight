import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { ApiError } from "@/lib/http";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { aiWorkflowValues } from "@/lib/types/ai/workflow";
import { aiImageStageValues } from "@/lib/types/ai/library";
import { closeDatabaseClientForTests } from "@/lib/supabase/postgres";
import {
    readAiLibrary,
    readAiCompanionImage,
} from "./ai-library-supabase-query";
import { adjustAiCredits } from "./ai-credits-supabase-query";
import {
    reserveAiRequest,
    finishAiRequestAttempt,
} from "./ai-requests-supabase-query";
import { readProfile, updateProfile } from "./profiles-supabase-query";
import { lookupSharedProfile } from "./shared-profiles-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
process.env.NEXT_PUBLIC_SUPABASE_URL = env.SUPABASE_TEST_URL;
process.env.SUPABASE_SECRET_KEY = env.SUPABASE_TEST_SERVICE_KEY;
const database = postgres(env.DATABASE_URL, { max: 5 });
after(async () => {
    await database.end();
    await closeDatabaseClientForTests();
});

test("completion saves Blend URLs atomically without media copies, preserves ownership and survives request pruning", async (t) => {
    const owner = randomUUID();
    const other = randomUUID();
    t.after(async () => {
        await database`delete from auth.users where id in (${owner}, ${other})`;
    });
    await database`insert into auth.users (id) values (${owner}), (${other})`;
    await database`update private.ai_provider_budget set requests = 0, starts = 0, remaining = null,
        reset_at = null, blocked_until = null, window_started_at = clock_timestamp(),
        starts_day = (clock_timestamp() at time zone 'UTC')::date where provider = 'blend'`;
    await adjustAiCredits(
        owner,
        {
            kind: "grant",
            user_id: owner,
            operation_key: randomUUID(),
            quantity: 10,
            reason: "test_library",
        },
        database,
    );
    const realFetch = globalThis.fetch;
    t.mock.method(
        globalThis,
        "fetch",
        async (...args: Parameters<typeof fetch>) => {
            const url =
                args[0] instanceof Request ? args[0].url : String(args[0]);
            assert.ok(
                !url.includes("tryblend.ai"),
                "Saving and selecting results must never fetch image bytes",
            );
            assert.ok(
                !url.includes("/storage/v1/"),
                "Blend images must not create or sign FitFight storage objects",
            );
            return realFetch(...args);
        },
    );
    const limits = {
        globalDailyStarts: 100,
        globalConcurrentRuns: 10,
        providerRequestsPerMinute: 100,
    };
    const version = { workflowId: "test", versionId: "test" };
    const ids: string[] = [];
    for (const workflow of aiWorkflowValues) {
        const admitted = await reserveAiRequest(
            owner,
            {
                workflow,
                description: "Fox with glasses",
                resourceId: null,
                idempotencyKey: randomUUID(),
                requestHash: "a".repeat(64),
                version,
                creditPrice: 1,
                sourceRequestIds: [],
            },
            limits,
            database,
        );
        const { request } = admitted;
        assert.ok(request.lease_token);
        const stages =
            workflow === "fitness"
                ? aiImageStageValues.filter((stage) => stage !== "image_url")
                : ["image_url"];
        const result = Object.fromEntries(
            stages.map((stage) => [
                stage,
                `https://supabase.tryblend.ai/${workflow}-${stage}.png`,
            ]),
        );
        const update = {
            status: "completed" as const,
            runHandle: { ...version, runId: randomUUID() },
            result,
            errorCode: null,
        };
        assert.deepEqual(await readAiLibrary(other, database), []);
        await finishAiRequestAttempt(
            owner,
            request.id,
            request.lease_token,
            update,
            {},
            database,
        );
        // A late duplicate completion cannot copy images or consume another credit.
        assert.equal(
            await finishAiRequestAttempt(
                owner,
                request.id,
                request.lease_token,
                update,
                {},
                database,
            ),
            null,
        );
        const saved = (await readAiLibrary(owner, database)).find(
            (entry) => entry.request_id === request.id,
        );
        assert.deepEqual(saved, {
            request_id: request.id,
            workflow,
            description: "Fox with glasses",
            images: stages.map((stage) => ({ stage, url: result[stage] })),
        });
        ids.push(request.id);
    }
    const selection = { request_id: ids[0], stage: "image_url" as const };
    await assert.rejects(
        readAiCompanionImage(other, selection, database),
        (error: unknown) => error instanceof ApiError && error.status === 404,
    );
    await assert.rejects(
        readAiCompanionImage(
            owner,
            { request_id: ids[2], stage: "image_url" },
            database,
        ),
        (error: unknown) => error instanceof ApiError && error.status === 404,
    );
    const selected = await updateProfile(owner, { companion_image: selection });
    assert.equal(
        selected.companion_image_url,
        "https://supabase.tryblend.ai/avatar-image_url.png",
    );
    assert.equal(selected.companion_id, "custom");
    assert.equal(selected.companion_prompt, "Fox with glasses");
    assert.equal(selected.avatar, null);
    assert.equal(
        (await lookupSharedProfile(other, selected.handle, database))
            .avatar_url,
        selected.companion_image_url,
    );
    // Existing profile commands preserve selection when omitted, and stock selection clears it.
    assert.equal(
        (await updateProfile(owner, { display_name: "New name" }))
            .companion_image_url,
        selected.companion_image_url,
    );
    await updateProfile(owner, { companion_id: "fox" });
    assert.equal((await readProfile(owner)).companion_image_url, undefined);
    const [media] =
        await database`select count(*)::int n from public.media_objects where owner_id = ${owner}`;
    assert.equal(media.n, 0);
    const [balance] =
        await database`select available, reserved from private.ai_credit_balances where user_id = ${owner}`;
    assert.deepEqual(balance, { available: 7, reserved: 0 });

    await database`update private.ai_requests set updated_at = clock_timestamp() - interval '8 days' where id = ${ids[0]}`;
    const derived = await reserveAiRequest(
        owner,
        {
            workflow: "fitness",
            description: "Fox with glasses",
            resourceId: null,
            idempotencyKey: randomUUID(),
            requestHash: "b".repeat(64),
            version,
            creditPrice: 1,
            sourceRequestIds: [ids[0]],
        },
        limits,
        database,
    );
    assert.ok(derived.shouldStart);
    if (derived.shouldStart)
        assert.deepEqual(derived.portraits, [selected.companion_image_url]);
    assert.equal(
        (
            await database`select id from private.ai_requests where id = ${ids[0]}`
        ).length,
        0,
    );
    assert.equal((await readAiLibrary(owner, database)).length, 3);
    assert.equal(
        (await readAiCompanionImage(owner, selection, database)).image_url,
        selected.companion_image_url,
    );
    await database`delete from auth.users where id = ${owner}`;
    assert.deepEqual(await readAiLibrary(owner, database), []);
});
