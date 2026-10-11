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
    chooseCustomCharacterPortrait,
    claimCustomCharacterPush,
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

    const otherTransactionId = BigInt(`0x${randomUUID().replaceAll("-", "")}`).toString();
    const otherPurchase = await recordCustomCharacterTransaction(appleCustomCharacterTransactionSchema.parse({
        ...receipt, transactionId: otherTransactionId, originalTransactionId: otherTransactionId, appAccountToken: otherAccount,
    }), database);
    const otherStart = await prepareCustomCharacterStage(other, otherPurchase.purchase_id, { description: "A gray owl" }, database);
    if (otherStart.kind !== "avatar") assert.fail("Expected a portrait stage");
    assert.ok((await dueCustomCharacterPurchases(database)).some((item) => item.id === otherPurchase.purchase_id));
    const blocker = await reserveAiRequest(other, {
        ...avatarInput, resourceId: null, idempotencyKey: randomUUID(), requestHash: "d".repeat(64), description: "An unpaid owl",
    }, limits, database);
    assert.equal(blocker.shouldStart, true);
    const otherInput = {
        ...avatarInput, resourceId: otherPurchase.purchase_id, idempotencyKey: otherStart.key,
        requestHash: "e".repeat(64), description: otherStart.description,
    };
    await assert.rejects(reserveAiRequest(other, otherInput, limits, database), { code: "ai_in_progress" });
    assert.equal((await dueCustomCharacterPurchases(database)).some((item) => item.id === otherPurchase.purchase_id), false);
    assert.ok(blocker.request.lease_token);
    await finishAiRequestAttempt(other, blocker.request.id, blocker.request.lease_token, {
        status: "failed", runHandle: null, result: null, errorCode: "ai_failed",
    }, {}, database);
    assert.ok((await dueCustomCharacterPurchases(database)).some((item) => item.id === otherPurchase.purchase_id));

    const otherRun = await reserveAiRequest(other, otherInput, limits, database);
    assert.equal(otherRun.shouldStart, true);
    await assert.rejects(prepareCustomCharacterStage(other, otherPurchase.purchase_id, { description: "A white owl" }, database), {
        code: "ai_request_conflict",
    });
    assert.ok(otherRun.request.lease_token);
    await finishAiRequestAttempt(other, otherRun.request.id, otherRun.request.lease_token, {
        status: "failed", runHandle: null, result: null, errorCode: "ai_failed",
    }, {}, database);
    const renamed = await prepareCustomCharacterStage(other, otherPurchase.purchase_id, { description: "A white owl" }, database);
    if (renamed.kind !== "avatar") assert.fail("Expected a portrait for the new description");
    assert.equal(renamed.description, "A white owl");
    assert.notEqual(renamed.key, otherStart.key);
    assert.equal((await readCustomCharacterStore(other, database)).characters[0].description, "A white owl");
    await assert.rejects(reserveAiRequest(other, { ...otherInput, idempotencyKey: renamed.key }, limits, database), {
        code: "ai_request_conflict",
    });
    const renamedRun = await reserveAiRequest(other, {
        ...otherInput, idempotencyKey: renamed.key, requestHash: "f".repeat(64), description: renamed.description,
    }, limits, database);
    assert.equal(renamedRun.shouldStart, true);
    assert.equal(renamedRun.request.description, "A white owl");
});

test("a description saved at claim draws three portraits; the owner picks one and only it feeds the poses", async (context) => {
    const owner = randomUUID();
    await database`insert into auth.users (id) values (${owner})`;
    await database`update private.ai_provider_budget set requests = 0, starts = 0, remaining = null,
        reset_at = null, blocked_until = null, window_started_at = clock_timestamp(),
        starts_day = (clock_timestamp() at time zone 'UTC')::date where provider = 'blend'`;
    const account = (await readSpecialStore(owner, database)).app_account_token;
    context.after(async () => {
        await database`delete from private.ai_library_images where user_id = ${owner}`;
        await database`delete from private.ai_requests where user_id = ${owner}`;
        await database`delete from private.custom_character_portraits where purchase_id in (
            select id from private.custom_character_purchases where account_id = ${account})`;
        await database`delete from private.custom_character_purchases where account_id = ${account}`;
        await database`delete from private.special_accounts where id = ${account}`;
        await database`delete from auth.users where id = ${owner}`;
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
    const claim = await recordCustomCharacterTransaction(receipt, database, "A red panda in a tracksuit");
    assert.equal((await recordCustomCharacterTransaction(receipt, database, "Another words")).purchase_id, claim.purchase_id);
    let character = (await readCustomCharacterStore(owner, database)).characters[0];
    assert.equal(character.description, "A red panda in a tracksuit");
    assert.equal(character.phase, "portraits");
    assert.equal(character.status, "generating");
    assert.equal(character.candidates.length, 3);
    assert.ok((await dueCustomCharacterPurchases(database)).some((item) => item.id === claim.purchase_id));

    const stage = await prepareCustomCharacterStage(owner, claim.purchase_id, {}, database);
    if (stage.kind !== "portraits") assert.fail("Expected three portraits");
    assert.equal(stage.starts.length, 3);
    const runs = [];
    for (const [index, key] of stage.starts.entries()) {
        const run = await reserveAiRequest(owner, {
            workflow: "avatar", resourceId: claim.purchase_id, idempotencyKey: key,
            requestHash: String(index).repeat(64), version, creditPrice: 0, sourceRequestIds: [], description: stage.description,
        }, limits, database);
        assert.equal(run.shouldStart, true);
        runs.push(run.request);
    }
    for (const [index, run] of runs.entries()) {
        assert.ok(run.lease_token);
        await finishAiRequestAttempt(owner, run.id, run.lease_token, index < 2
            ? { status: "completed", runHandle: { ...version, runId: randomUUID() },
                result: { image_url: `https://cdn.tryblend.ai/candidate-${index}.png` }, errorCode: null }
            : { status: "failed", runHandle: null, result: null, errorCode: "ai_failed" }, {}, database);
    }
    character = (await readCustomCharacterStore(owner, database)).characters[0];
    assert.equal(character.phase, "choosing");
    assert.equal(character.status, "generating");
    assert.deepEqual(character.candidates.map((item) => item.status), ["completed", "completed", "failed"]);
    assert.equal(character.portrait_url, null);
    assert.ok((await dueCustomCharacterPurchases(database)).some((item) => item.id === claim.purchase_id));
    assert.equal(await claimCustomCharacterPush(owner, claim.purchase_id, "portraits", database), true);
    assert.equal(await claimCustomCharacterPush(owner, claim.purchase_id, "portraits", database), false);

    const [first, second, failed] = character.candidates;
    await assert.rejects(chooseCustomCharacterPortrait(owner, claim.purchase_id, failed.id, database), {
        code: "character_portrait_not_ready",
    });
    await chooseCustomCharacterPortrait(owner, claim.purchase_id, second.id, database);
    await chooseCustomCharacterPortrait(owner, claim.purchase_id, second.id, database);
    await assert.rejects(chooseCustomCharacterPortrait(owner, claim.purchase_id, first.id, database), {
        code: "character_portrait_chosen",
    });
    character = (await readCustomCharacterStore(owner, database)).characters[0];
    assert.equal(character.phase, "poses");
    assert.equal(character.stage, "fitness");
    assert.equal(character.portrait_url, "https://cdn.tryblend.ai/candidate-1.png");
    assert.equal((await database`select count(*)::int as count from private.custom_character_portraits
        where purchase_id = ${claim.purchase_id} and selected_at is null`)[0].count, 2);

    const fitness = await prepareCustomCharacterStage(owner, claim.purchase_id, {}, database);
    if (fitness.kind !== "fitness") assert.fail("Expected the poses stage");
    assert.equal(fitness.avatarRequestId, runs[1].id);
    const fitnessInput = {
        workflow: "fitness" as const, resourceId: claim.purchase_id, idempotencyKey: fitness.key,
        requestHash: "f".repeat(64), version, creditPrice: 0, description: fitness.description,
    };
    await assert.rejects(reserveAiRequest(owner, { ...fitnessInput, sourceRequestIds: [runs[0].id] }, limits, database), {
        code: "not_found",
    });
    const poses = await reserveAiRequest(owner, { ...fitnessInput, sourceRequestIds: [runs[1].id] }, limits, database);
    if (!poses.shouldStart) assert.fail("Expected the poses to start");
    assert.deepEqual(poses.portraits, ["https://cdn.tryblend.ai/candidate-1.png"]);
});
