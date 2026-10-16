import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { GET as store } from "@/app/api/v1/me/custom-characters/route";
import { POST as claim } from "@/app/api/v1/me/custom-characters/purchases/route";
import { POST as advance } from "@/app/api/v1/me/custom-characters/[purchaseID]/advance/route";
import { POST as choose } from "@/app/api/v1/me/custom-characters/[purchaseID]/choose/route";
import { POST as label } from "@/app/api/v1/me/custom-characters/[purchaseID]/label/route";
import { POST as suggestions } from "@/app/api/v1/me/custom-characters/[purchaseID]/suggestions/route";
import {
    customCharacterAdvanceRequestSchema,
    customCharacterChooseRequestSchema,
    customCharacterClaimRequestSchema,
    customCharacterLabelRequestSchema,
    customCharacterStoreSchema,
    customCharacterSuggestionsRequestSchema,
    companionLinesBatchSchema,
    type CompanionLinesStep,
} from "@/lib/types/ai/custom-character";
import { blendWorkflowConfiguration } from "@/lib/blend/workflows";
import { blendConfiguration, type AiRunResponse, type CreateAiRunRequest } from "@/lib/types/ai/workflow";
import { ApiError } from "@/lib/http";
import { advanceCompanionLines, advanceCompanionLinesBestEffort } from "./paid-character";

test("paid character routes require authentication and reject caller-owned purchase metadata", async () => {
    const purchaseID = "22222222-2222-4222-8222-222222222222";
    const responses = await Promise.all([
        store(new Request("https://fitfight.app/api/v1/me/custom-characters"), { params: Promise.resolve({}) }),
        claim(new Request("https://fitfight.app/api/v1/me/custom-characters/purchases", {
            method: "POST", body: JSON.stringify({ signed_transaction: "receipt" }),
        }), { params: Promise.resolve({}) }),
        advance(new Request(`https://fitfight.app/api/v1/me/custom-characters/${purchaseID}/advance`, {
            method: "POST", body: JSON.stringify({ description: "Fox" }),
        }), { params: Promise.resolve({ purchaseID }) }),
        choose(new Request(`https://fitfight.app/api/v1/me/custom-characters/${purchaseID}/choose`, {
            method: "POST", body: JSON.stringify({ candidate_id: purchaseID }),
        }), { params: Promise.resolve({ purchaseID }) }),
    ]);
    assert.ok(responses.every((response) => response.status === 401));
    assert.equal(customCharacterClaimRequestSchema.safeParse({
        signed_transaction: "receipt", account_id: purchaseID,
    }).success, false);
    assert.equal(customCharacterAdvanceRequestSchema.safeParse({
        description: "Fox", product_id: "another-product",
    }).success, false);
    // Older apps send these exact bodies; they must stay valid.
    assert.equal(customCharacterClaimRequestSchema.safeParse({ signed_transaction: "receipt" }).success, true);
    assert.equal(customCharacterAdvanceRequestSchema.safeParse({ description: "Fox" }).success, true);
    assert.equal(customCharacterAdvanceRequestSchema.safeParse({ retry: true }).success, true);
    assert.equal(customCharacterChooseRequestSchema.safeParse({ candidate_id: "not-a-uuid" }).success, false);
});

test("paid portrait and fitness starts require no operator credit price", () => {
    const previousApiKey = process.env.BLEND_API_KEY;
    const previousPrice = blendConfiguration.workflows.fitness.creditPrice;
    try {
        process.env.BLEND_API_KEY = "bai_test-only-blend-key";
        blendConfiguration.workflows.fitness.creditPrice = undefined;
        assert.equal(blendWorkflowConfiguration("avatar", true).creditPrice, 0);
        assert.equal(blendWorkflowConfiguration("fitness", true).creditPrice, 0);
        assert.throws(() => blendWorkflowConfiguration("fitness"), { code: "ai_unavailable" });
    } finally {
        blendConfiguration.workflows.fitness.creditPrice = previousPrice;
        if (previousApiKey === undefined) delete process.env.BLEND_API_KEY;
        else process.env.BLEND_API_KEY = previousApiKey;
    }
});


const purchaseID = "22222222-2222-4222-8222-222222222222";
const ownerID = "11111111-1111-4111-8111-111111111111";

test("label and suggestion routes require authentication before reading the body", async () => {
    const responses = await Promise.all([
        label(new Request(`https://fitfight.app/api/v1/me/custom-characters/${purchaseID}/label`, {
            method: "POST", body: JSON.stringify({ name: "Max", line: "Walks like rent is due." }),
        }), { params: Promise.resolve({ purchaseID }) }),
        suggestions(new Request(`https://fitfight.app/api/v1/me/custom-characters/${purchaseID}/suggestions`, {
            method: "POST", body: JSON.stringify({ attempt_id: purchaseID }),
        }), { params: Promise.resolve({ purchaseID }) }),
    ]);
    assert.ok(responses.every((response) => response.status === 401));
});

test("a saved name and line are trimmed single lines within 24 and 60 characters", () => {
    assert.deepEqual(customCharacterLabelRequestSchema.parse({ name: "  Max ", line: " Walks like rent is due. " }), {
        name: "Max", line: "Walks like rent is due.",
    });
    assert.ok(customCharacterLabelRequestSchema.safeParse({ name: "n".repeat(24), line: "l".repeat(60) }).success);
    for (const invalid of [
        { name: "n".repeat(25), line: "Fine" },
        { name: "Max", line: "l".repeat(61) },
        { name: " ", line: "Fine" },
        { name: "Max", line: "" },
        { name: "Max" },
        { name: "Max\nPower", line: "Fine" },
        { name: "Max", line: "One\rTwo" },
        { name: "Max", line: "Fine", purchase_id: purchaseID },
        { name: 4, line: "Fine" },
    ])
        assert.equal(customCharacterLabelRequestSchema.safeParse(invalid).success, false, JSON.stringify(invalid));
    assert.ok(customCharacterSuggestionsRequestSchema.safeParse({ attempt_id: purchaseID }).success);
    for (const invalid of [{}, { attempt_id: "again" }, { attempt_id: purchaseID, avoid: [] }])
        assert.equal(customCharacterSuggestionsRequestSchema.safeParse(invalid).success, false);
});

test("suggestions use the owner's newest installation language: French only when it is French", async () => {
    for (const [locale, language] of [["fr", "fr"], ["en", "en"], [null, "en"], ["de", "en"]] as const) {
        const started: CreateAiRunRequest[] = [];
        const changed = await advanceCompanionLines(ownerID, purchaseID, null, {
            prepare: async (): Promise<CompanionLinesStep> => ({
                kind: "start",
                key: "44444444-4444-4444-8444-444444444444",
                description: "A pigeon in a hoodie",
                avatarRequestId: "55555555-5555-4555-8555-555555555555",
                locale,
                avoid: [{ name: "Max", line: "Walks like rent is due." }],
            }),
            start: async (owner, input, key, _deps, resource) => {
                assert.equal(owner, ownerID);
                assert.equal(key, "44444444-4444-4444-8444-444444444444");
                assert.equal(resource, purchaseID);
                started.push(input);
                return { request_id: key, workflow: "companion_lines", status: "pending", poll_after_seconds: 3 };
            },
            read: async () => assert.fail("A start step reads nothing"),
        });
        assert.deepEqual(started, [{
            workflow: "companion_lines",
            parameters: {
                avatar_request_id: "55555555-5555-4555-8555-555555555555",
                description: "A pigeon in a hoodie",
                language,
                avoid: [{ name: "Max", line: "Walks like rent is due." }],
            },
        }]);
        assert.equal(changed, true);
    }
});

test("a running batch is read on every advance and a finished one starts nothing", async () => {
    const read: string[] = [];
    const deps = (step: CompanionLinesStep, settled = false) => ({
        prepare: async () => step,
        start: async () => assert.fail("Nothing to start"),
        read: async (_owner: string, requestId: string): Promise<AiRunResponse> => {
            read.push(requestId);
            return settled
                ? { request_id: requestId, workflow: "companion_lines", status: "failed", code: "ai_failed", error: "Failed" }
                : { request_id: requestId, workflow: "companion_lines", status: "running", poll_after_seconds: 10 };
        },
    });
    // Only a settled batch changes the character, so advance reads the store again only then.
    assert.equal(await advanceCompanionLines(ownerID, purchaseID, null, deps({ kind: "pending", requestId: purchaseID })), false);
    assert.equal(await advanceCompanionLines(ownerID, purchaseID, null, deps({ kind: "pending", requestId: purchaseID }, true)), true);
    assert.equal(await advanceCompanionLines(ownerID, purchaseID, null, deps({ kind: "none" })), false);
    assert.deepEqual(read, [purchaseID, purchaseID]);
});

test("the background suggestion step never breaks poses: rejections are kept quiet or logged without text", async (t) => {
    const errors = t.mock.method(console, "error", () => {});
    assert.equal(await advanceCompanionLinesBestEffort(ownerID, purchaseID, async () => true), true);
    for (const code of ["ai_busy", "ai_unavailable", "ai_rate_limited", "ai_daily_limit", "ai_in_progress"] as const)
        assert.equal(await advanceCompanionLinesBestEffort(ownerID, purchaseID, async () => {
            throw new ApiError(503, code, "Deferred");
        }), false);
    assert.equal(errors.mock.callCount(), 0);
    assert.equal(await advanceCompanionLinesBestEffort(ownerID, purchaseID, async () => {
        throw new ApiError(502, "ai_status_unavailable", "Walks like rent is due.");
    }), false);
    assert.deepEqual(errors.mock.calls.map((call) => call.arguments), [[
        "fitfight_companion_lines_failed",
        JSON.stringify({ error_code: "ai_status_unavailable", purchase_id: purchaseID }),
    ]]);
    await assert.rejects(advanceCompanionLinesBestEffort(ownerID, purchaseID, async () => {
        throw new TypeError("Unexpected");
    }), TypeError);
});

test("stored suggestions are read as saved, even past today's limits", () => {
    const stored = { name: "n".repeat(30), line: "Two\nlines and ".repeat(6) };
    const batch = {
        id: purchaseID,
        resource_id: purchaseID,
        idempotency_key: ownerID,
        status: "completed",
        result: { options: [stored] },
    };
    assert.deepEqual(companionLinesBatchSchema.parse(batch).result?.options, [stored]);
    assert.equal(customCharacterLabelRequestSchema.safeParse(stored).success, false);
});

test("suggestion batches are free for a character and closed to credit starts", () => {
    const previousApiKey = process.env.BLEND_API_KEY;
    try {
        process.env.BLEND_API_KEY = "bai_test-only-blend-key";
        assert.equal(blendWorkflowConfiguration("companion_lines", true).creditPrice, 0);
        assert.throws(() => blendWorkflowConfiguration("companion_lines"), { code: "ai_unavailable" });
    } finally {
        if (previousApiKey === undefined) delete process.env.BLEND_API_KEY;
        else process.env.BLEND_API_KEY = previousApiKey;
    }
    assert.equal(blendConfiguration.workflows.companion_lines.creditPrice, undefined);
});

test("the store fixture with suggestions matches the server contract", () => {
    const fixture: unknown = JSON.parse(readFileSync(
        new URL("../../../../contracts/fixtures/custom-character-store.json", import.meta.url), "utf8",
    ));
    assert.deepEqual(customCharacterStoreSchema.parse(fixture), fixture);
});
