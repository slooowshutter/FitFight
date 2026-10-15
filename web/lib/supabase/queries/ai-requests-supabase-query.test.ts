import assert from "node:assert/strict";
import { test } from "node:test";
import type { Sql } from "postgres";
import type { AiRequestRecord } from "@/lib/types/ai/request";
import { claimAiRequestPoll, finishAiRequestAttempt } from "./ai-requests-supabase-query";

const userId = "11111111-1111-4111-8111-111111111111";
const requestId = "22222222-2222-4222-8222-222222222222";
const lease = "33333333-3333-4333-8333-333333333333";
const limits = { globalDailyStarts: 500, globalConcurrentRuns: 10, providerRequestsPerMinute: 60 };
const run = { workflowId: "lines-publication", runId: "lines-run" };

function record(workflow: AiRequestRecord["workflow"], status: AiRequestRecord["status"]) {
    return {
        id: requestId,
        user_id: userId,
        workflow,
        description: "A pigeon in a hoodie",
        resource_id: null,
        idempotency_key: requestId,
        request_hash: "a".repeat(64),
        workflow_version: { workflowId: run.workflowId },
        run_handle: status === "starting" ? null : run,
        status,
        result: null,
        error_code: null,
        created_at: new Date(),
        updated_at: new Date(),
        lease_token: lease,
        lease_expires_at: null,
        next_poll_at: new Date(),
        source_request_ids: [],
        credit_price: 0,
        credit_state: "none",
        admitted_at: new Date(),
        submission_attempted_at: null,
        acknowledged_at: null,
        provider_completed_at: null,
        terminal_observed_at: null,
        settled_at: null,
        recovery_operation_key: null,
        recovery_actor: null,
        recovery_evidence: null,
    };
}

/** Answers each query by its text and returns the delay bound into the update that sets next_poll_at. */
function pollDelayDatabase(row: ReturnType<typeof record>) {
    const delays: unknown[] = [];
    const sql = ((strings: TemplateStringsArray, ...values: unknown[]) => {
        const text = strings.join("?").replace(/\s+/g, " ");
        const delay = strings.findIndex((part) => /next_poll_at = (greatest\(next_poll_at, )?clock_timestamp\(\) \+ $/.test(part));
        if (delay >= 0) delays.push(values[delay]);
        if (text.includes("as poll_due")) return Promise.resolve([{ ...row, poll_due: true }]);
        if (text.includes("as observed_at, window_started_at"))
            return Promise.resolve([{
                observed_at: new Date(),
                window_started_at: new Date(),
                requests: 0,
                starts_day: "2026-10-15",
                starts: 0,
                remaining: null,
                reset_at: null,
                blocked_until: null,
            }]);
        if (text.includes("from private.ai_requests where id") || text.includes("returning *"))
            return Promise.resolve([row]);
        return Promise.resolve([]);
    }) as unknown as Sql;
    Object.assign(sql, {
        begin: async (callback: (transaction: Sql) => Promise<unknown>) => callback(sql),
        json: (value: unknown) => value,
    });
    return { database: sql, delays };
}

test("a suggestion batch is first read 30 s after its start, then every 10 s; other runs keep 3 s", async () => {
    for (const [workflow, status, expected] of [
        ["companion_lines", "starting", ["30 seconds"]],
        ["companion_lines", "running", ["10 seconds"]],
        ["avatar", "starting", ["3 seconds"]],
        ["fitness", "running", ["3 seconds"]],
    ] as const) {
        const { database, delays } = pollDelayDatabase(record(workflow, status));
        await finishAiRequestAttempt(userId, requestId, lease, {
            status: "pending",
            runHandle: run,
            result: null,
            errorCode: null,
        }, {}, database);
        assert.deepEqual(delays, expected, `${workflow} ${status}`);
    }
    for (const [workflow, expected] of [["companion_lines", ["10 seconds"]], ["avatar", ["3 seconds"]]] as const) {
        const { database, delays } = pollDelayDatabase(record(workflow, "running"));
        const claimed = await claimAiRequestPoll(userId, requestId, limits, database, "reconciler");
        assert.equal(claimed.shouldPoll, true);
        assert.deepEqual(delays, expected, workflow);
    }
});
