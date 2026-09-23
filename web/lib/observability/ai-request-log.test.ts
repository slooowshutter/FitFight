import assert from "node:assert/strict";
import { after, test } from "node:test";
import { ApiError, apiRoute, json } from "@/lib/http";
import { setServerErrorLogWriter } from "@/lib/observability/server-error-log";
import {
    correlateAiRequest,
    observeAiCall,
    observeAiHttp,
    setAiHttpLogWriter,
} from "./ai-request-log";
import type { AiHttpLog } from "@/lib/types/ai/observation";

const trace = "11111111-1111-4111-8111-111111111111";
const user = "22222222-2222-4222-8222-222222222222";
const requestId = "33333333-3333-4333-8333-333333333333";
after(() => {
    setAiHttpLogWriter(null);
    setServerErrorLogWriter(null);
});

test("HTTP summaries correlate every leg and record a terminal failure carried by HTTP 200", async () => {
    const batches: AiHttpLog[][] = [];
    setAiHttpLogWriter(async (rows) => {
        batches.push(rows);
    });
    const handler = observeAiHttp(
        apiRoute(async () => {
            correlateAiRequest(
                {
                    user_id: user,
                    request_id: requestId,
                    workflow_id: "avatar",
                    version_id: "pinned",
                    run_id: "run",
                },
                "observed",
            );
            observeAiCall({
                leg: "blend",
                operation: "read",
                status: 200,
                elapsed_ms: 12,
                outcome: null,
                code: null,
                upstream_code: null,
            });
            return json({
                request_id: requestId,
                status: "failed",
                code: "ai_failed",
                error: "Safe error",
                description: "never-log-this",
                data: { trace: "never-log-provider" },
            });
        }),
        "read",
    );
    const response = await handler(
        new Request(
            "https://fitfight.app/api/v1/ai/runs/id?prompt=never-log-query",
            {
                headers: {
                    Authorization: "Bearer never-log-token",
                    "X-FitFight-Trace-ID": trace,
                },
            },
        ),
        { params: Promise.resolve({}) },
    );
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("X-FitFight-Trace-ID"), trace);
    assert.match(
        response.headers.get("Server-Timing") ?? "",
        /^total;dur=\d+$/,
    );
    assert.equal(batches[0].length, 2);
    for (const log of batches[0]) {
        assert.equal(log.trace_id, trace);
        assert.equal(log.request_id, requestId);
        assert.equal(log.run_id, "run");
        assert.ok(log.elapsed_ms >= 0);
    }
    assert.equal(batches[0][1].outcome, "failed");
    assert.equal(batches[0][1].code, "ai_failed");
    assert.ok(!JSON.stringify(batches).includes("never-log"));
});

test("duplicate recovery and rejected calls are distinguished, with bounded logs", async () => {
    const batches: AiHttpLog[][] = [];
    setAiHttpLogWriter(async (rows) => {
        batches.push(rows);
    });
    setServerErrorLogWriter(async () => {});
    for (const rejected of [false, true]) {
        const handler = observeAiHttp(
            apiRoute(async () => {
                correlateAiRequest({ request_id: requestId }, "recovered");
                if (rejected)
                    throw new ApiError(
                        503,
                        "ai_busy",
                        "Busy",
                        {
                            upstream: {
                                status: 429,
                                code: "rate_limit_exceeded",
                            },
                        },
                        { request_id: requestId },
                    );
                for (let index = 0; index < 12; index++)
                    observeAiCall({
                        leg: "blend",
                        operation: "read",
                        status: 200,
                        elapsed_ms: 1,
                        outcome: null,
                        code: null,
                        upstream_code: null,
                    });
                return json({ request_id: requestId, status: "pending" }, 202);
            }),
            "start",
        );
        const response = await handler(
            new Request("https://fitfight.app/api/v1/ai/runs", {
                headers: { "X-FitFight-Trace-ID": "invalid" },
            }),
            { params: Promise.resolve({}) },
        );
        assert.notEqual(response.headers.get("X-FitFight-Trace-ID"), "invalid");
    }
    assert.equal(batches[0].length, 9);
    assert.equal(batches[0][8].disposition, "recovered");
    assert.equal(batches[1][0].disposition, "rejected");
    assert.equal(batches[1][0].code, "ai_busy");
});

test("log storage failure preserves the prepared result and concurrent traces stay isolated", async () => {
    const captured: AiHttpLog[] = [];
    setAiHttpLogWriter(async (rows) => {
        captured.push(...rows);
        throw new Error("diagnostic sink unavailable");
    });
    const handler = observeAiHttp(
        apiRoute(async (request) => {
            const id = request.headers.get("X-FitFight-Trace-ID");
            await Promise.resolve();
            return json({ request_id: id, status: "pending" }, 202);
        }),
        "start",
    );
    const responses = await Promise.all(
        [trace, requestId].map((id) =>
            handler(
                new Request("https://fitfight.app/api/v1/ai/runs", {
                    headers: { "X-FitFight-Trace-ID": id },
                }),
                { params: Promise.resolve({}) },
            ),
        ),
    );
    assert.ok(responses.every((response) => response.status === 202));
    assert.equal(captured.length, 2);
    assert.ok(captured.every((log) => log.request_id === log.trace_id));
});
