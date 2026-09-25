import assert from "node:assert/strict";
import { test } from "node:test";
import { GET as store } from "@/app/api/v1/me/custom-characters/route";
import { POST as claim } from "@/app/api/v1/me/custom-characters/purchases/route";
import { POST as advance } from "@/app/api/v1/me/custom-characters/[purchaseID]/advance/route";
import {
    customCharacterAdvanceRequestSchema,
    customCharacterClaimRequestSchema,
} from "@/lib/types/ai/custom-character";
import { blendWorkflowConfiguration } from "@/lib/blend/workflows";

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
    ]);
    assert.ok(responses.every((response) => response.status === 401));
    assert.equal(customCharacterClaimRequestSchema.safeParse({
        signed_transaction: "receipt", account_id: purchaseID,
    }).success, false);
    assert.equal(customCharacterAdvanceRequestSchema.safeParse({
        description: "Fox", product_id: "another-product",
    }).success, false);
});

test("paid portrait and fitness starts require no operator credit price", () => {
    const previous = {
        BLEND_API_KEY: process.env.BLEND_API_KEY,
        BLEND_ENABLED: process.env.BLEND_ENABLED,
        BLEND_GLOBAL_DAILY_STARTS: process.env.BLEND_GLOBAL_DAILY_STARTS,
        BLEND_GLOBAL_CONCURRENT_RUNS: process.env.BLEND_GLOBAL_CONCURRENT_RUNS,
        BLEND_REQUESTS_PER_MINUTE: process.env.BLEND_REQUESTS_PER_MINUTE,
        BLEND_AVATAR_WORKFLOW_ID: process.env.BLEND_AVATAR_WORKFLOW_ID,
        BLEND_AVATAR_VERSION_ID: process.env.BLEND_AVATAR_VERSION_ID,
        BLEND_FITNESS_WORKFLOW_ID: process.env.BLEND_FITNESS_WORKFLOW_ID,
        BLEND_FITNESS_VERSION_ID: process.env.BLEND_FITNESS_VERSION_ID,
        BLEND_FITNESS_CREDIT_PRICE: process.env.BLEND_FITNESS_CREDIT_PRICE,
    };
    try {
        Object.assign(process.env, {
            BLEND_API_KEY: "bai_test-only-blend-key",
            BLEND_ENABLED: "true",
            BLEND_GLOBAL_DAILY_STARTS: "100",
            BLEND_GLOBAL_CONCURRENT_RUNS: "10",
            BLEND_REQUESTS_PER_MINUTE: "100",
            BLEND_AVATAR_WORKFLOW_ID: "avatar-publication",
            BLEND_AVATAR_VERSION_ID: "avatar-version",
            BLEND_FITNESS_WORKFLOW_ID: "fitness-publication",
            BLEND_FITNESS_VERSION_ID: "fitness-version",
        });
        delete process.env.BLEND_FITNESS_CREDIT_PRICE;
        assert.equal(blendWorkflowConfiguration("avatar", true).creditPrice, 0);
        assert.equal(blendWorkflowConfiguration("fitness", true).creditPrice, 0);
        assert.throws(() => blendWorkflowConfiguration("fitness"), { code: "ai_unavailable" });
    } finally {
        for (const [key, value] of Object.entries(previous)) {
            if (value === undefined) delete process.env[key];
            else process.env[key] = value;
        }
    }
});
