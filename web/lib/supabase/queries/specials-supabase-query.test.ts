import assert from "node:assert/strict";
import { test } from "node:test";
import { GET } from "@/app/api/v1/me/specials/route";
import { POST as checkout } from "@/app/api/v1/me/specials/checkout/route";
import { POST as claim } from "@/app/api/v1/me/specials/transactions/route";
import { POST as notify } from "@/app/api/apple/specials/notifications/[environment]/route";
import {
    specialCheckoutRequestSchema,
    specialClaimRequestSchema,
} from "@/lib/types/companions/specials";

for (const [path, handler] of [
    ["", GET],
    ["/checkout", checkout],
    ["/transactions", claim],
] as const) {
    test(`Specials ${path || "store"} requires authentication before reading or writing purchases`, async () => {
        const response = await handler(
            new Request(
                `https://staging.fitfight.app/api/v1/me/specials${path}`,
            ),
            { params: Promise.resolve({}) },
        );
        assert.equal(response.status, 401);
        assert.equal(response.headers.get("cache-control"), "no-store");
    });
}

test("checkout cannot supply an owner, environment, price or entitlement", () => {
    const input = {
        action: "reserve",
        companion_id: "limited-pangolin",
        attempt_id: "6283b4c1-0e8f-4caa-b04b-827b6f1e925b",
    };
    assert.equal(specialCheckoutRequestSchema.safeParse(input).success, true);
    for (const extra of [
        { user_id: input.attempt_id },
        { environment: "Production" },
        { price: 0 },
        { owned: true },
    ]) {
        assert.equal(
            specialCheckoutRequestSchema.safeParse({ ...input, ...extra })
                .success,
            false,
        );
    }
    assert.equal(
        specialCheckoutRequestSchema.safeParse({
            ...input,
            companion_id: "fox",
        }).success,
        false,
    );
    assert.equal(
        specialClaimRequestSchema.safeParse({
            companion_id: "limited-pangolin",
            signed_transaction: "",
        }).success,
        false,
    );
});

test("notifications reject unknown environments, wrong deployments and unsigned payloads", async () => {
    process.env.APPLE_IAP_ENVIRONMENT = "Sandbox";
    for (const [path, status, body] of [
        ["invalid", 404, {}],
        ["production", 400, {}],
        ["sandbox", 400, {}],
        ["sandbox", 400, { signedPayload: "forged" }],
    ] as const) {
        const response = await notify(
            new Request(
                `https://staging.fitfight.app/api/apple/specials/notifications/${path}`,
                {
                    method: "POST",
                    body: JSON.stringify(body),
                },
            ),
            { params: Promise.resolve({ environment: path }) },
        );
        assert.equal(response.status, status);
    }
});
