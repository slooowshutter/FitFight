import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { ApiError, errorResponse } from "@/lib/http";
import { redactSecrets } from "@/lib/observability/server-error-log";
import { startBlendWorkflow, readBlendWorkflowRun } from "./client";

const workflow = {
    workflowId: "published-workflow",
    versionId: "pinned-version",
};
const handle = { ...workflow, runId: "owned-run" };
const apiKey = process.env.BLEND_API_KEY;

before(() => {
    process.env.BLEND_API_KEY = "bai_test_secret_for_contracts";
});
after(() => {
    if (apiKey === undefined) delete process.env.BLEND_API_KEY;
    else process.env.BLEND_API_KEY = apiKey;
});

test("start pins a workflow and returns a durable handle without assuming synchronous output", async () => {
    const result = await startBlendWorkflow(
        workflow,
        { description: "An athletic fox" },
        async (url, options) => {
            assert.equal(url, "https://www.tryblend.ai/api/v1/responses");
            assert.equal(options?.method, "POST");
            assert.equal(options?.redirect, "error");
            assert.equal(options?.cache, "no-store");
            assert.equal(
                new Headers(options.headers).get("Authorization"),
                "Bearer bai_test_secret_for_contracts",
            );
            assert.equal(
                options.body,
                JSON.stringify({
                    ...workflow,
                    inputs: { description: "An athletic fox" },
                    stream: false,
                }),
            );
            assert.ok(options.signal);
            return Response.json(
                {
                    run_id: "owned-run",
                    status: "pending",
                    created_at: "2026-09-17T00:00:00Z",
                },
                {
                    status: 202,
                    headers: {
                        "X-RateLimit-Remaining": "7",
                        "X-RateLimit-Reset": "1790000000000",
                    },
                },
            );
        },
    );
    assert.deepEqual(result, {
        data: handle,
        rateLimit: { remaining: 7, resetAt: 1790000000000 },
    });
});

test("missing credentials cannot submit a workflow", async () => {
    delete process.env.BLEND_API_KEY;
    try {
        await assert.rejects(
            startBlendWorkflow(workflow, {}, async () => {
                assert.fail("A missing key must not reach Blend");
            }),
            (error: unknown) =>
                error instanceof ApiError && error.code === "ai_unavailable",
        );
    } finally {
        process.env.BLEND_API_KEY = "bai_test_secret_for_contracts";
    }
});

test("lost, malformed, or ambiguous start responses never trigger an automatic second POST", async (t) => {
    for (const outcome of [
        "network",
        "timeout",
        "html",
        "invalid-json",
        "500",
        "wrong-version",
        "wrong-workflow",
        "wrong-status",
    ]) {
        await t.test(outcome, async () => {
            let calls = 0;
            await assert.rejects(
                startBlendWorkflow(workflow, {}, async () => {
                    calls += 1;
                    if (outcome === "network")
                        throw new TypeError("Connection lost with secret body");
                    if (outcome === "timeout")
                        throw new DOMException(
                            "Provider timeout",
                            "TimeoutError",
                        );
                    if (outcome === "html")
                        return new Response("upstream content", {
                            status: 202,
                        });
                    if (outcome === "invalid-json")
                        return Response.json(
                            { run_id: "owned-run" },
                            { status: 202 },
                        );
                    if (outcome === "500")
                        return Response.json(
                            {
                                error: {
                                    message: "secret",
                                    code: "workflow_graph_corrupt",
                                },
                            },
                            { status: 500 },
                        );
                    return Response.json(
                        {
                            run_id: "owned-run",
                            status: "pending",
                            created_at: "2026-09-17T00:00:00Z",
                            published_workflow_id:
                                outcome === "wrong-workflow"
                                    ? "other-workflow"
                                    : workflow.workflowId,
                            published_workflow_version_id:
                                outcome === "wrong-version"
                                    ? "other-version"
                                    : workflow.versionId,
                        },
                        { status: outcome === "wrong-status" ? 200 : 202 },
                    );
                }),
                (error: unknown) => {
                    assert.ok(error instanceof ApiError);
                    assert.equal(error.code, "ai_start_unconfirmed");
                    assert.equal(error.message.includes("secret"), false);
                    return true;
                },
            );
            assert.equal(calls, 1);
        });
    }
});

test("provider account and configuration failures do not ask the app user to pay or sign in", async (t) => {
    for (const status of [400, 401, 402, 404]) {
        await t.test(String(status), async () => {
            await assert.rejects(
                startBlendWorkflow(workflow, {}, async () =>
                    Response.json(
                        {
                            error: {
                                code: "insufficient_credits",
                                message: "SECRET provider account details",
                            },
                        },
                        { status },
                    ),
                ),
                (error: unknown) => {
                    assert.ok(error instanceof ApiError);
                    assert.equal(error.status, 503);
                    assert.equal(error.code, "ai_unavailable");
                    assert.equal(
                        JSON.stringify(error).includes("SECRET"),
                        false,
                    );
                    return true;
                },
            );
        });
    }
});

test("provider throttling exposes a safe retry delay, not its error body", async () => {
    await assert.rejects(
        startBlendWorkflow(workflow, {}, async () =>
            Response.json(
                {
                    error: { code: "rate_limit_exceeded", message: "SECRET" },
                },
                {
                    status: 429,
                    headers: {
                        "Retry-After": "12",
                        "X-RateLimit-Remaining": "0",
                        "X-RateLimit-Reset": "1790000000000",
                    },
                },
            ),
        ),
        (error: unknown) => {
            assert.ok(error instanceof ApiError);
            assert.equal(error.code, "ai_busy");
            assert.equal(error.clientContext.retry_after_seconds, 12);
            assert.deepEqual(error.detail, {
                upstream: { status: 429, code: "rate_limit_exceeded" },
                rateLimit: {
                    remaining: 0,
                    resetAt: 1790000000000,
                    retryAfterSeconds: 12,
                },
            });
            return true;
        },
    );
});

test("reads preserve every documented state and never create another run", async (t) => {
    for (const status of [
        "pending",
        "running",
        "completed",
        "failed",
        "cancelled",
    ]) {
        await t.test(status, async () => {
            const result = await readBlendWorkflowRun(
                handle,
                async (url, options) => {
                    assert.equal(
                        url,
                        "https://www.tryblend.ai/api/v1/runs/owned-run",
                    );
                    assert.equal(options?.method, "GET");
                    assert.equal(options?.body, undefined);
                    return Response.json({
                        id: "owned-run",
                        status,
                        output:
                            status === "completed"
                                ? {
                                      avatar: [
                                          {
                                              id: "item",
                                              item_index: 0,
                                              status: "failed",
                                              parts: [],
                                              error: {
                                                  message: "SECRET",
                                                  code: 123,
                                              },
                                          },
                                      ],
                                  }
                                : null,
                        error: "SECRET provider detail",
                        published_workflow_version_id: null,
                    });
                },
            );
            assert.equal(result.data.status, status);
            assert.equal(JSON.stringify(result).includes("SECRET"), false);
            if (status === "completed") {
                assert.equal(result.data.output?.avatar[0].status, "failed");
            }
        });
    }
});

test("text, JSON, and media parts keep their typed values for feature decoding", async () => {
    const parts = [
        { type: "text", text: "Summary" },
        { type: "json", data: { recap: "Summary" } },
        { type: "image", url: "https://example.com/image.png" },
        { type: "video", url: "https://example.com/video.mp4" },
        {
            type: "file",
            url: "https://example.com/audio.mp3",
            mime_type: "audio/mpeg",
        },
    ];
    const result = await readBlendWorkflowRun(handle, async () =>
        Response.json({
            id: handle.runId,
            status: "completed",
            output: {
                result: [
                    { id: "item", item_index: 0, status: "completed", parts },
                ],
            },
        }),
    );
    assert.deepEqual(result.data.output?.result[0].parts, parts);
});

test("read failures retain the known run and suppress unsafe rate-limit headers", async (t) => {
    for (const outcome of [
        "network",
        "wrong-run",
        "wrong-version",
        "invalid",
        "invalid-part",
    ]) {
        await t.test(outcome, async () => {
            let calls = 0;
            await assert.rejects(
                readBlendWorkflowRun(handle, async () => {
                    calls += 1;
                    if (outcome === "network") throw new Error("lost");
                    return Response.json(
                        {
                            id:
                                outcome === "wrong-run"
                                    ? "another-run"
                                    : handle.runId,
                            status:
                                outcome === "invalid" ? "unknown" : "completed",
                            published_workflow_version_id:
                                outcome === "wrong-version"
                                    ? "another-version"
                                    : workflow.versionId,
                            output:
                                outcome === "invalid-part"
                                    ? {
                                          result: [
                                              {
                                                  id: "item",
                                                  item_index: 0,
                                                  status: "completed",
                                                  parts: [
                                                      {
                                                          type: "image",
                                                          url: "not-a-url",
                                                      },
                                                  ],
                                              },
                                          ],
                                      }
                                    : null,
                        },
                        {
                            headers: {
                                "X-RateLimit-Remaining": "-1",
                                "X-RateLimit-Reset": "Infinity",
                                "Retry-After": "secret",
                            },
                        },
                    );
                }),
                (error: unknown) =>
                    error instanceof ApiError &&
                    error.code ===
                        (outcome === "invalid-part"
                            ? "ai_invalid_result"
                            : "ai_status_unavailable"),
            );
            assert.equal(calls, 1);
        });
    }
});

test("existing errors retain their wire shape; AI metadata is explicit and provider details stay private", async () => {
    const legacy = errorResponse(
        new ApiError(400, "validation", "Check your input"),
    );
    assert.deepEqual(await legacy.json(), {
        error: "Check your input",
        code: "validation",
    });
    assert.equal(legacy.headers.has("Retry-After"), false);

    const response = errorResponse(
        new ApiError(
            429,
            "ai_rate_limited",
            "Try again later.",
            {
                upstream: { status: 429, secret: "must stay private" },
            },
            {
                request_id: "11111111-1111-4111-8111-111111111111",
                retry_after_seconds: 10,
            },
        ),
    );
    assert.equal(response.status, 429);
    assert.equal(response.headers.get("Retry-After"), "10");
    assert.deepEqual(await response.json(), {
        error: "Try again later.",
        code: "ai_rate_limited",
        request_id: "11111111-1111-4111-8111-111111111111",
        retry_after_seconds: 10,
    });
    assert.equal(
        redactSecrets("BLEND_API_KEY=bai_test_secret_for_contracts"),
        "BLEND_API_KEY=[redacted]",
    );
});

test("provider completion time survives output validation and failed terminal output cannot strand a hold", async () => {
    const completedAt = "2026-09-18T10:00:00Z";
    const failed = await readBlendWorkflowRun(handle, async () =>
        Response.json({
            id: handle.runId,
            status: "failed",
            completed_at: completedAt,
            output: "malformed but irrelevant to a confirmed failed run",
        }),
    );
    assert.equal(failed.data.status, "failed");
    assert.equal(failed.data.completed_at, completedAt);
    assert.equal(failed.data.output, null);
    await assert.rejects(
        readBlendWorkflowRun(handle, async () =>
            Response.json({
                id: handle.runId,
                status: "completed",
                completed_at: completedAt,
                output: "invalid terminal output",
            }),
        ),
        (error: unknown) =>
            error instanceof ApiError &&
            error.code === "ai_invalid_result" &&
            typeof error.detail === "object" &&
            error.detail !== null &&
            Reflect.get(error.detail, "providerCompletedAt") === completedAt,
    );
});
