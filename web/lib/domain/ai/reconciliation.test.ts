import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { after, test } from "node:test";
import { ApiError } from "@/lib/http";
import { requireAiOperator } from "./operators";
import { reconcileAiRuns } from "./reconciliation";
import {
    aiAllowanceSchema,
    aiCreditAdjustmentSchema,
    aiRecoverySchema,
} from "@/lib/types/ai/credits";
import { aiRequestRecordSchema } from "@/lib/types/ai/request";
import { setAiHttpLogWriter } from "@/lib/observability/ai-request-log";
import { setServerErrorLogWriter } from "@/lib/observability/server-error-log";

const userId = "11111111-1111-4111-8111-111111111111";
const requestId = "22222222-2222-4222-8222-222222222222";
const originalOperator = process.env.FITFIGHT_ADMIN_USER_ID;
after(() => {
    if (originalOperator === undefined)
        delete process.env.FITFIGHT_ADMIN_USER_ID;
    else process.env.FITFIGHT_ADMIN_USER_ID = originalOperator;
    setAiHttpLogWriter(null);
    setServerErrorLogWriter(null);
});

function pendingRequest(id = requestId) {
    return aiRequestRecordSchema.parse({
        id,
        user_id: userId,
        workflow: "avatar",
        description: "Fox",
        resource_id: null,
        idempotency_key: id,
        request_hash: "a".repeat(64),
        workflow_version: { workflowId: "avatar", versionId: "pinned" },
        run_handle: { workflowId: "avatar", versionId: "pinned", runId: id },
        status: "pending",
        result: null,
        error_code: null,
        source_request_ids: [],
        credit_price: 1,
        credit_state: "reserved",
        created_at: new Date(),
        updated_at: new Date(),
        next_poll_at: new Date(),
        lease_token: null,
        lease_expires_at: null,
        admitted_at: new Date(),
        submission_attempted_at: new Date(),
        acknowledged_at: new Date(),
        terminal_observed_at: null,
        provider_completed_at: null,
        settled_at: null,
        recovery_actor: null,
        recovery_operation_key: null,
        recovery_evidence: null,
    });
}

test("allowance fixture and operator boundaries do not permit client-selected prices or grants", () => {
    const raw: unknown = JSON.parse(
        readFileSync(
            new URL(
                "../../../../contracts/fixtures/ai-allowance.json",
                import.meta.url,
            ),
            "utf8",
        ),
    );
    assert.deepEqual(aiAllowanceSchema.parse(raw), {
        available: 2,
        reserved: 1,
        avatar_price: 1,
    });
    delete process.env.FITFIGHT_ADMIN_USER_ID;
    assert.throws(
        () => requireAiOperator(userId),
        (error: unknown) => error instanceof ApiError && error.status === 403,
    );
    process.env.FITFIGHT_ADMIN_USER_ID = userId;
    assert.doesNotThrow(() => requireAiOperator(userId));
    assert.throws(() => requireAiOperator(requestId));
    const grant = {
        kind: "grant",
        user_id: userId,
        operation_key: requestId,
        quantity: 1,
        reason: "explicit_grant",
    };
    assert.ok(aiCreditAdjustmentSchema.safeParse(grant).success);
    const mixedCaseKey = "ABCDEFAB-1234-4234-8234-ABCDEFABCDEF";
    assert.equal(
        aiCreditAdjustmentSchema.parse({
            ...grant,
            operation_key: mixedCaseKey,
        }).operation_key,
        mixedCaseKey.toLowerCase(),
    );
    for (const invalid of [
        { ...grant, quantity: -1 },
        { ...grant, actor: userId },
        { ...grant, price: 1 },
    ]) {
        assert.equal(
            aiCreditAdjustmentSchema.safeParse(invalid).success,
            false,
        );
    }
    assert.equal(
        aiRecoverySchema.safeParse({
            action: "confirm_not_accepted",
            operation_key: requestId,
        }).success,
        false,
    );
});

test("reconciliation observes abandoned results with the server caller path and stops on provider cooldown", async () => {
    let pruned = false;
    let count = 0;
    const result = await reconcileAiRuns({
        pruneLogs: async () => {
            pruned = true;
        },
        due: async () => [
            pendingRequest(),
            pendingRequest(userId),
            pendingRequest(),
        ],
        read: async (owner, id, _deps, source) => {
            assert.equal(owner, userId);
            assert.equal(source, "reconciler");
            if (++count === 2) throw new ApiError(503, "ai_busy", "Cooldown");
            return {
                request_id: id,
                workflow: "avatar",
        description: "Fox",
                status: "completed",
                data: { image_url: "https://cdn.tryblend.ai/avatar.png" },
            };
        },
    });
    assert.equal(pruned, true);
    assert.equal(count, 2);
    assert.deepEqual(result, { checked: 1, settled: 1 });
});

test("transient status failure is not settlement and does not block the next known run", async () => {
    let count = 0;
    const result = await reconcileAiRuns({
        pruneLogs: async () => {},
        due: async () => [pendingRequest(), pendingRequest(userId)],
        read: async (_owner, id) => {
            if (++count === 1)
                throw new ApiError(503, "ai_status_unavailable", "Uncertain");
            return {
                request_id: id,
                workflow: "avatar",
        description: "Fox",
                status: "failed",
                code: "ai_invalid_result",
                error: "Invalid output",
            };
        },
    });
    assert.deepEqual(result, { checked: 1, settled: 1 });
});

test("allowance and operator routes require authentication; cron cannot be called with a user token", async () => {
    setAiHttpLogWriter(async () => {});
    setServerErrorLogWriter(async () => {});
    const allowance = await import("@/app/api/v1/ai/allowance/route");
    const credits = await import("@/app/api/internal/ai/credits/route");
    const recovery = await import(
        "@/app/api/internal/ai/requests/[requestID]/recover/route"
    );
    const cron = await import("@/app/api/internal/ai/reconcile/route");
    const responses = [
        await allowance.GET(
            new Request("https://fitfight.app/api/v1/ai/allowance"),
            { params: Promise.resolve({}) },
        ),
        await credits.POST(
            new Request("https://fitfight.app/api/internal/ai/credits", {
                method: "POST",
                body: "not-json",
            }),
            { params: Promise.resolve({}) },
        ),
        await recovery.POST(
            new Request(
                "https://fitfight.app/api/internal/ai/requests/id/recover",
                { method: "POST", body: "not-json" },
            ),
            { params: Promise.resolve({ requestID: "invalid" }) },
        ),
    ];
    assert.ok(responses.every((response) => response.status === 401));
    const original = process.env.CRON_SECRET;
    process.env.CRON_SECRET = "test-only-cron-secret";
    try {
        const response = await cron.GET(
            new Request("https://fitfight.app/api/internal/ai/reconcile", {
                headers: { Authorization: "Bearer a-user-token" },
            }),
            { params: Promise.resolve({}) },
        );
        assert.equal(response.status, 401);
    } finally {
        if (original === undefined) delete process.env.CRON_SECRET;
        else process.env.CRON_SECRET = original;
    }
});
