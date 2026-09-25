import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { appleCustomCharacterTransactionSchema, customCharacterProductId } from "@/lib/types/apple/custom-character-purchase";
import { readAiLibrary } from "./ai-library-supabase-query";
import { reserveAiRequest, finishAiRequestAttempt } from "./ai-requests-supabase-query";
import {
    readCustomCharacterStore,
    recordCustomCharacterTransaction,
    prepareCustomCharacterStage,
    dueCustomCharacterPurchases,
} from "./custom-characters-supabase-query";
import { readSpecialStore } from "./specials-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
process.env.APPLE_IAP_ENVIRONMENT = "Sandbox";
process.env.APPLE_SPECIALS_ENABLED = "true";
process.env.APPLE_CUSTOM_CHARACTERS_ENABLED = "true";
const database = postgres(env.DATABASE_URL, { max: 5 });
after(() => database.end());
const version = { workflowId: "paid-character-test", versionId: "published-test" };
const limits = { globalDailyStarts: 100, globalConcurrentRuns: 10, providerRequestsPerMinute: 100 };

test("each verified consumable funds exactly one recoverable portrait and five-image set", async (context) => {
    const owner = randomUUID();
    const other = randomUUID();
    await database`insert into auth.users (id) values (${owner}), (${other})`;
    await database`update private.ai_provider_budget set requests = 0, starts = 0, remaining = null,
        reset_at = null, blocked_until = null, window_started_at = clock_timestamp(),
        starts_day = (clock_timestamp() at time zone 'UTC')::date where provider = 'blend'`;
    const account = (await readSpecialStore(owner, database)).app_account_token;
    const otherAccount = (await readSpecialStore(other, database)).app_account_token;
    context.after(async () => {
        await database`delete from private.ai_library_images where user_id in (${owner}, ${other})`;
        await database`delete from private.ai_requests where user_id in (${owner}, ${other})`;
        await database`delete from private.custom_character_purchases where account_id in (${account}, ${otherAccount})`;
        await database`delete from private.special_accounts where id in (${account}, ${otherAccount})`;
        await database`delete from auth.users where id in (${owner}, ${other})`;
    });
    const transactionId = BigInt(`0x${randomUUID().replaceAll("-", "")}`).toString();
    const receipt = appleCustomCharacterTransactionSchema.parse({
        transactionId,
        originalTransactionId: transactionId,
        bundleId: "com.fitfight.mvp",
        productId: customCharacterProductId,
        environment: "Sandbox",
        type: "Consumable",
        inAppOwnershipType: "PURCHASED",
        quantity: 1,
        appAccountToken: account,
        purchaseDate: Date.now(),
        signedDate: Date.now() + 1_000,
    });
    const first = await recordCustomCharacterTransaction(receipt, database);
    assert.equal(first.refunded, false);
    assert.equal((await recordCustomCharacterTransaction(receipt, database)).purchase_id, first.purchase_id);
    await assert.rejects(recordCustomCharacterTransaction({ ...receipt, appAccountToken: otherAccount }, database), {
        code: "character_account",
    });
    assert.equal((await readCustomCharacterStore(owner, database)).characters[0].status, "ready");
    assert.equal((await readCustomCharacterStore(other, database)).characters.length, 0);

    const start = await prepareCustomCharacterStage(owner, first.purchase_id, { description: "A fox with green glasses" }, database);
    assert.equal(start.kind, "avatar");
    if (start.kind !== "avatar") assert.fail("Expected portrait stage");
    assert.deepEqual(await prepareCustomCharacterStage(owner, first.purchase_id, {}, database), start);
    await assert.rejects(prepareCustomCharacterStage(other, first.purchase_id, {}, database), { status: 404 });
    await assert.rejects(prepareCustomCharacterStage(owner, first.purchase_id, { description: "Another fox" }, database), { status: 409 });
    const avatarInput = {
        workflow: "avatar" as const,
        resourceId: first.purchase_id,
        idempotencyKey: start.key,
        requestHash: "a".repeat(64),
        version,
        creditPrice: 0,
        sourceRequestIds: [],
        description: start.description,
    };
    await assert.rejects(reserveAiRequest(other, avatarInput, limits, database), { code: "character_purchase_required" });
    await assert.rejects(reserveAiRequest(owner, { ...avatarInput, idempotencyKey: randomUUID() }, limits, database), { code: "ai_request_conflict" });
    const admitted = await reserveAiRequest(owner, avatarInput, limits, database);
    assert.equal(admitted.shouldStart, true);
    const recovered = await reserveAiRequest(owner, avatarInput, limits, database);
    assert.equal(recovered.request.id, admitted.request.id);
    assert.equal((await database`select count(*)::int as count from private.ai_balance_events where request_id = ${admitted.request.id}`)[0].count, 0);
    assert.ok(admitted.request.lease_token);
    await finishAiRequestAttempt(owner, admitted.request.id, admitted.request.lease_token, {
        status: "completed",
        runHandle: { ...version, runId: randomUUID() },
        result: { image_url: "https://cdn.tryblend.ai/paid-portrait.png" },
        errorCode: null,
    }, {}, database);
    assert.equal((await readCustomCharacterStore(owner, database)).characters[0].stage, "fitness");
    assert.ok((await dueCustomCharacterPurchases(database)).some((item) => item.id === first.purchase_id));

    const fitness = await prepareCustomCharacterStage(owner, first.purchase_id, {}, database);
    assert.equal(fitness.kind, "fitness");
    if (fitness.kind !== "fitness") assert.fail("Expected fitness stage");
    assert.equal(fitness.avatarRequestId, admitted.request.id);
    const fitnessInput = {
        workflow: "fitness" as const,
        resourceId: first.purchase_id,
        idempotencyKey: fitness.key,
        requestHash: "b".repeat(64),
        version,
        creditPrice: 0,
        sourceRequestIds: [admitted.request.id],
        description: fitness.description,
    };
    const fitnessRun = await reserveAiRequest(owner, fitnessInput, limits, database);
    assert.equal(fitnessRun.shouldStart, true);
    if (!fitnessRun.shouldStart) assert.fail("Expected first fitness admission");
    assert.deepEqual(fitnessRun.portraits, ["https://cdn.tryblend.ai/paid-portrait.png"]);
    assert.ok(fitnessRun.request.lease_token);
    const stages = ["resting", "soft", "average", "fit", "strong"];
    const images = Object.fromEntries(stages.map((stage) => [stage, `https://cdn.tryblend.ai/paid-${stage}.png`]));
    await finishAiRequestAttempt(owner, fitnessRun.request.id, fitnessRun.request.lease_token, {
        status: "completed",
        runHandle: { ...version, runId: randomUUID() },
        result: images,
        errorCode: null,
    }, {}, database);
    assert.equal((await readCustomCharacterStore(owner, database)).characters[0].status, "complete");
    assert.equal((await readAiLibrary(owner, database)).find((item) => item.request_id === fitnessRun.request.id)?.images.length, 5);
    assert.equal((await dueCustomCharacterPurchases(database)).some((item) => item.id === first.purchase_id), false);
    assert.deepEqual(await prepareCustomCharacterStage(owner, first.purchase_id, {}, database), {
        kind: "existing", requestId: fitnessRun.request.id,
    });

    await database`update public.profiles set companion_id = 'custom', companion_prompt = ${start.description},
        companion_image_url = ${images.resting} where id = ${owner}`;
    const refunded = appleCustomCharacterTransactionSchema.parse({ ...receipt,
        signedDate: receipt.signedDate + 2_000, revocationDate: receipt.signedDate + 1_000,
    });
    assert.equal((await recordCustomCharacterTransaction(refunded, database)).refunded, true);
    assert.equal((await readAiLibrary(owner, database)).some((item) => item.request_id === fitnessRun.request.id), false);
    assert.equal((await database`select companion_image_url from public.profiles where id = ${owner}`)[0].companion_image_url, null);
    await recordCustomCharacterTransaction(receipt, database);
    assert.equal((await readCustomCharacterStore(owner, database)).characters[0].status, "refunded");
    await recordCustomCharacterTransaction(appleCustomCharacterTransactionSchema.parse({
        ...receipt, signedDate: refunded.signedDate + 1_000,
    }), database);
    assert.equal((await readCustomCharacterStore(owner, database)).characters[0].status, "complete");
    assert.equal((await readAiLibrary(owner, database)).find((item) => item.request_id === fitnessRun.request.id)?.images.length, 5);

    const secondTransactionId = BigInt(`0x${randomUUID().replaceAll("-", "")}`).toString();
    const second = await recordCustomCharacterTransaction(appleCustomCharacterTransactionSchema.parse({
        ...receipt, transactionId: secondTransactionId, originalTransactionId: secondTransactionId,
    }), database);
    assert.notEqual(second.purchase_id, first.purchase_id);
    assert.equal((await readCustomCharacterStore(owner, database)).characters.length, 2);
    assert.equal((await readCustomCharacterStore(owner, database)).characters.find((item) => item.id === second.purchase_id)?.status, "ready");
    const secondStart = await prepareCustomCharacterStage(owner, second.purchase_id, { description: "A blue heron" }, database);
    assert.equal(secondStart.kind, "avatar");
    if (secondStart.kind !== "avatar") assert.fail("Expected a new portrait stage");
    const secondRun = await reserveAiRequest(owner, {
        ...avatarInput, resourceId: second.purchase_id, idempotencyKey: secondStart.key,
        description: secondStart.description, requestHash: "c".repeat(64),
    }, limits, database);
    assert.ok(secondRun.request.lease_token);
    await finishAiRequestAttempt(owner, secondRun.request.id, secondRun.request.lease_token, {
        status: "failed", runHandle: null, result: null, errorCode: "ai_failed",
    }, {}, database);
    assert.equal((await readCustomCharacterStore(owner, database)).characters.find((item) => item.id === second.purchase_id)?.status, "retryable");
    assert.equal((await dueCustomCharacterPurchases(database)).some((item) => item.id === second.purchase_id), false);
    const secondRetry = await prepareCustomCharacterStage(owner, second.purchase_id, { retry: true }, database);
    assert.equal(secondRetry.kind, "avatar");
    if (secondRetry.kind !== "avatar") assert.fail("Expected a portrait retry");
    assert.notEqual(secondRetry.key, secondStart.key);
});
