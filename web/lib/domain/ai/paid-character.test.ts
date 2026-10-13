import assert from "node:assert/strict";
import { test } from "node:test";
import { GET as store } from "@/app/api/v1/me/custom-characters/route";
import { POST as claim } from "@/app/api/v1/me/custom-characters/purchases/route";
import { POST as advance } from "@/app/api/v1/me/custom-characters/[purchaseID]/advance/route";
import { POST as choose } from "@/app/api/v1/me/custom-characters/[purchaseID]/choose/route";
import {
    customCharacterAdvanceRequestSchema,
    customCharacterChooseRequestSchema,
    customCharacterClaimRequestSchema,
} from "@/lib/types/ai/custom-character";
import { blendWorkflowConfiguration } from "@/lib/blend/workflows";
import { blendConfiguration } from "@/lib/types/ai/workflow";

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

