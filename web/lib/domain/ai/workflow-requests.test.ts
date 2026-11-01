import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { after, before, test } from "node:test";
import { ApiError } from "@/lib/http";
import type { AiRequestDependencies } from "@/lib/types/ai/service";
import {
    aiRequestRecordSchema,
    type AiRequestRecord,
} from "@/lib/types/ai/request";
import {
    aiRunResponseSchema,
    blendCompanionLinesOutputSchema,
    blendConfiguration,
    createAiRunRequestSchema,
    legacyAvatarVersionId,
} from "@/lib/types/ai/workflow";
import { blendRunResponseSchema } from "@/lib/types/blend/workflow";
import { startAiRun, readAiRun } from "./workflow-requests";

const userId = "11111111-1111-4111-8111-111111111111";
const requestId = "22222222-2222-4222-8222-222222222222";
const key = "33333333-3333-4333-8333-333333333333";
const lease = "44444444-4444-4444-8444-444444444444";
const version = { workflowId: "published-avatar", versionId: "pinned-avatar" };
const run = { ...version, runId: "avatar-run" };
const input = createAiRunRequestSchema.parse({
    workflow: "avatar",
    parameters: { description: "A fox with glasses" },
});
const testConfiguration: typeof blendConfiguration = {
    limits: {
        globalDailyStarts: 100,
        globalConcurrentRuns: 2,
        providerRequestsPerMinute: 30,
    },
    workflows: {
        avatar: { runner: "blend", ...version, creditPrice: 1 },
        fitness: {
            runner: "blend",
            workflowId: "fitness-publication",
            versionId: "fitness-version",
            creditPrice: 5,
        },
        group_photo: {
            runner: "blend",
            workflowId: "group-publication",
            versionId: "group-version",
            creditPrice: 2,
        },
        companion_lines: {
            runner: "blend",
            workflowId: "lines-publication",
            versionId: "lines-version",
        },
        prompt_check: {
            runner: "blend",
            workflowId: "check-publication",
            versionId: "check-version",
        },
    },
};
const originalConfiguration = { ...blendConfiguration };
const originalApiKey = process.env.BLEND_API_KEY;
before(() => {
    process.env.BLEND_API_KEY = "bai_test_key";
    Object.assign(blendConfiguration, testConfiguration);
});
after(() => {
    Object.assign(blendConfiguration, originalConfiguration);
    if (originalApiKey === undefined) delete process.env.BLEND_API_KEY;
    else process.env.BLEND_API_KEY = originalApiKey;
});

function requestRecord(
    overrides: Partial<AiRequestRecord> = {},
): AiRequestRecord {
    return aiRequestRecordSchema.parse({
        id: requestId,
        user_id: userId,
        workflow: "avatar",
        description: "A fox with glasses",
        resource_id: null,
        idempotency_key: key,
        request_hash: "a".repeat(64),
        workflow_version: version,
        run_handle: null,
        status: "starting",
        result: null,
        error_code: null,
        created_at: new Date(),
        updated_at: new Date(),
        lease_token: lease,
        lease_expires_at: new Date(Date.now() + 30_000),
        next_poll_at: new Date(),
        source_request_ids: [],
        credit_price: 1,
        credit_state: "reserved",
        admitted_at: new Date(),
        submission_attempted_at: null,
        acknowledged_at: null,
        provider_completed_at: null,
        terminal_observed_at: null,
        settled_at: null,
        recovery_operation_key: null,
        recovery_actor: null,
        recovery_evidence: null,
        ...overrides,
    });
}

function requestDependencies(
    record: AiRequestRecord,
    overrides: Partial<AiRequestDependencies> = {},
): AiRequestDependencies {
    return {
        reserve: async () => ({
            request: record,
            shouldStart: true,
            portraits: [],
        }),
        submit: async () => {},
        claim: async () => ({ request: record, shouldPoll: true }),
        start: async () => ({ data: run, rateLimit: {} }),
        read: async () => ({
            data: { id: run.runId, status: "running", output: null },
            rateLimit: {},
        }),
        finish: async (owner, id, token, update) => {
            assert.equal(owner, userId);
            assert.equal(id, requestId);
            assert.equal(token, lease);
            return requestRecord({
                ...record,
                status: update.status,
                run_handle: update.runHandle,
                result: update.result,
                error_code: update.errorCode,
                lease_token: null,
                lease_expires_at: null,
            });
        },
        ...overrides,
    };
}

test("avatar start reserves a caller-owned action before using the saved published input contract", async () => {
    let admitted = false;
    const response = await startAiRun(
        userId,
        input,
        key,
        requestDependencies(requestRecord(), {
            reserve: async (owner, reservation) => {
                admitted = true;
                assert.equal(owner, userId);
                assert.equal(reservation.resourceId, null);
                assert.equal(reservation.idempotencyKey, key);
                assert.equal(reservation.requestHash.length, 64);
                assert.equal(reservation.description, "A fox with glasses");
                return {
                    request: requestRecord(),
                    shouldStart: true,
                    portraits: [],
                };
            },
            start: async (selected, inputs) => {
                assert.equal(admitted, true);
                assert.deepEqual(selected, version);
                assert.deepEqual(inputs, {
                    describe_your_animal: "A fox with glasses",
                });
                return { data: run, rateLimit: {} };
            },
        }),
    );
    assert.deepEqual(response, {
        request_id: requestId,
        workflow: "avatar",
        status: "pending",
        poll_after_seconds: 3,
    });
});

test("uncertain starts preserve the reservation and attach its request ID to the app error", async () => {
    let saved = false;
    await assert.rejects(
        startAiRun(
            userId,
            input,
            key,
            requestDependencies(requestRecord(), {
                start: async () => {
                    throw new ApiError(
                        503,
                        "ai_start_unconfirmed",
                        "Could not confirm start",
                    );
                },
                finish: async (_owner, _id, _token, update) => {
                    saved = true;
                    assert.equal(update.status, "start_unconfirmed");
                    assert.equal(update.errorCode, "ai_start_unconfirmed");
                    assert.equal(update.runHandle, null);
                    return requestRecord({
                        status: "start_unconfirmed",
                        error_code: "ai_start_unconfirmed",
                    });
                },
            }),
        ),
        (error: unknown) =>
            error instanceof ApiError &&
            error.code === "ai_start_unconfirmed" &&
            error.clientContext.request_id === requestId,
    );
    assert.equal(saved, true);
});

test("accepted run followed by persistence failure stays uncertain and retains run ID only in diagnostics", async () => {
    await assert.rejects(
        startAiRun(
            userId,
            input,
            key,
            requestDependencies(requestRecord(), {
                finish: async () => {
                    throw new Error("database disconnected");
                },
            }),
        ),
        (error: unknown) => {
            assert.ok(error instanceof ApiError);
            assert.equal(error.code, "ai_start_unconfirmed");
            assert.equal(error.clientContext.request_id, requestId);
            assert.deepEqual(error.detail, {
                request_id: requestId,
                workflow_id: version.workflowId,
                version_id: version.versionId,
                run_id: run.runId,
            });
            return true;
        },
    );
});

test("known run reads use owner-scoped storage and the original version, even after a newer version is configured", async () => {
    blendConfiguration.workflows.avatar.versionId = "new-version";
    try {
        const record = requestRecord({ status: "pending", run_handle: run });
        const response = await readAiRun(
            userId,
            requestId,
            requestDependencies(record, {
                claim: async (owner, id) => {
                    assert.equal(owner, userId);
                    assert.equal(id, requestId);
                    return { request: record, shouldPoll: true };
                },
                read: async (handle) => {
                    assert.deepEqual(handle, run);
                    return {
                        data: { id: run.runId, status: "running" },
                        rateLimit: {},
                    };
                },
                start: async () =>
                    assert.fail("Reading cannot start a workflow"),
            }),
        );
        assert.equal(response.status, "running");
    } finally {
        blendConfiguration.workflows.avatar.versionId = version.versionId;
    }
});

test("completed avatar output becomes domain data; invalid and partially failed output become terminal app errors", async (t) => {
    for (const outcome of [
        "image",
        "failed-item",
        "missing",
        "extra-image",
        "untrusted-url",
        "cancelled",
        "failed",
    ]) {
        await t.test(outcome, async () => {
            const record = requestRecord({
                status: "running",
                run_handle: run,
            });
            const response = await readAiRun(
                userId,
                requestId,
                requestDependencies(record, {
                    read: async () => ({
                        data: {
                            id: run.runId,
                            status:
                                outcome === "cancelled"
                                    ? "cancelled"
                                    : outcome === "failed"
                                      ? "failed"
                                      : "completed",
                            output:
                                outcome === "missing"
                                    ? null
                                    : {
                                          avatar: Array.from(
                                              {
                                                  length:
                                                      outcome === "extra-image"
                                                          ? 2
                                                          : 1,
                                              },
                                              (_, index) => ({
                                                  id: `item-${index}`,
                                                  item_index: index,
                                                  status:
                                                      outcome === "failed-item"
                                                          ? "failed"
                                                          : "completed",
                                                  parts: [
                                                      {
                                                          type: "image",
                                                          url:
                                                              outcome ===
                                                              "untrusted-url"
                                                                  ? "https://attacker.invalid/image.png"
                                                                  : "https://supabase.tryblend.ai/storage/v1/object/public/generated/test/image",
                                                      },
                                                  ],
                                              }),
                                          ),
                                      },
                        },
                        rateLimit: {},
                    }),
                }),
            );
            if (outcome === "image") {
                assert.equal(response.status, "completed");
                if (
                    response.status === "completed" &&
                    response.workflow === "avatar"
                )
                    assert.match(
                        response.data.image_url,
                        /^https:\/\/supabase.tryblend.ai\//,
                    );
            } else {
                assert.ok(
                    response.status === "failed" ||
                        response.status === "cancelled",
                );
                assert.equal(
                    response.code,
                    outcome === "cancelled"
                        ? "ai_cancelled"
                        : ["failed", "failed-item"].includes(outcome)
                          ? "ai_failed"
                          : "ai_invalid_result",
                );
            }
        });
    }
});

test("status outages keep the known run resumable; malformed completed envelopes fail the request", async (t) => {
    for (const code of [
        "ai_status_unavailable",
        "ai_invalid_result",
    ] as const) {
        await t.test(code, async () => {
            const record = requestRecord({
                status: "running",
                run_handle: run,
            });
            let savedState = "";
            const promise = readAiRun(
                userId,
                requestId,
                requestDependencies(record, {
                    read: async () => {
                        throw new ApiError(503, code, "Safe provider failure");
                    },
                    finish: async (_owner, _id, _token, update) => {
                        savedState = update.status;
                        assert.deepEqual(update.runHandle, run);
                        return requestRecord({
                            ...record,
                            status: update.status,
                            error_code: update.errorCode,
                        });
                    },
                }),
            );
            if (code === "ai_invalid_result") {
                assert.equal((await promise).status, "failed");
                assert.equal(savedState, "failed");
            } else {
                await assert.rejects(
                    promise,
                    (error: unknown) =>
                        error instanceof ApiError &&
                        error.clientContext.request_id === requestId,
                );
                assert.equal(savedState, "running");
            }
        });
    }
});

test("request contract rejects arbitrary workflows, provider settings, empty descriptions and oversized prompts", () => {
    for (const raw of [
        { workflow: "arbitrary", parameters: { description: "Fox" } },
        { ...input, workflowId: "attacker-controlled" },
        {
            workflow: "avatar",
            parameters: { description: "Fox", model: "expensive" },
        },
        { workflow: "avatar", parameters: { description: " " } },
        { workflow: "avatar", parameters: { description: "a".repeat(1001) } },
    ]) {
        assert.equal(createAiRunRequestSchema.safeParse(raw).success, false);
    }
});

test("failed persistence after an upstream rejection still returns the recovery request ID", async () => {
    await assert.rejects(
        startAiRun(
            userId,
            input,
            key,
            requestDependencies(requestRecord(), {
                start: async () => {
                    throw new ApiError(
                        503,
                        "ai_busy",
                        "AI is busy. Try again later.",
                    );
                },
                finish: async () => {
                    throw new Error("database connection lost");
                },
            }),
        ),
        (error: unknown) =>
            error instanceof ApiError &&
            error.code === "ai_start_unconfirmed" &&
            error.clientContext.request_id === requestId,
    );
});

test("shared Swift fixtures match the server run contract", () => {
    for (const name of [
        "ai-run-pending.json",
        "ai-run-completed.json",
        "ai-run-unconfirmed.json",
        "ai-run-fitness.json",
        "ai-run-group-photo.json",
    ]) {
        const fixture: unknown = JSON.parse(
            readFileSync(
                new URL(
                    `../../../../contracts/fixtures/${name}`,
                    import.meta.url,
                ),
                "utf8",
            ),
        );
        assert.deepEqual(aiRunResponseSchema.parse(fixture), fixture);
    }
});

test("AI routes authenticate before request parsing or paid-work admission", async () => {
    const startRoute = await import("@/app/api/v1/ai/runs/route");
    const readRoute = await import("@/app/api/v1/ai/runs/[requestID]/route");
    const start = await startRoute.POST(
        new Request("https://fitfight.app/api/v1/ai/runs", {
            method: "POST",
            body: "not json",
        }),
        { params: Promise.resolve({}) },
    );
    const read = await readRoute.GET(
        new Request("https://fitfight.app/api/v1/ai/runs/invalid"),
        {
            params: Promise.resolve({ requestID: "invalid" }),
        },
    );
    for (const response of [start, read]) {
        assert.equal(response.status, 401);
        assert.deepEqual(await response.json(), {
            error: "Missing bearer token",
            code: "unauthorized",
        });
        assert.equal(response.headers.get("Cache-Control"), "no-store");
    }
    assert.equal(
        startRoute.OPTIONS(new Request("https://fitfight.app/api/v1/ai/runs"))
            .status,
        204,
    );
});

test("removed start configuration still recovers an existing action key", async () => {
    const workflowId = blendConfiguration.workflows.avatar.workflowId;
    blendConfiguration.workflows.avatar.workflowId = "";
    try {
        const result = await startAiRun(
            userId,
            input,
            key,
            requestDependencies(requestRecord(), {
                reserve: async () => ({
                    request: requestRecord(),
                    shouldStart: false,
                }),
                start: async () =>
                    assert.fail("Recovery cannot submit paid work"),
            }),
        );
        assert.equal(result.request_id, requestId);
    } finally {
        blendConfiguration.workflows.avatar.workflowId = workflowId;
    }
});

test("a superseded start rejection remains recoverable and a stale invalid-result read cannot claim settlement", async () => {
    await assert.rejects(
        startAiRun(
            userId,
            input,
            key,
            requestDependencies(requestRecord(), {
                start: async () => {
                    throw new ApiError(503, "ai_busy", "Busy");
                },
                finish: async () => null,
            }),
        ),
        (error: unknown) =>
            error instanceof ApiError &&
            error.code === "ai_start_unconfirmed" &&
            error.clientContext.request_id === requestId,
    );
    await assert.rejects(
        readAiRun(
            userId,
            requestId,
            requestDependencies(
                requestRecord({ status: "pending", run_handle: run }),
                {
                    read: async () => {
                        throw new ApiError(502, "ai_invalid_result", "Invalid");
                    },
                    finish: async () => null,
                },
            ),
        ),
        (error: unknown) =>
            error instanceof ApiError && error.code === "ai_status_unavailable",
    );
});

test("fitness and group adapters use owned portraits, exact labels, cast order and their stored prices", async () => {
    const secondId = "55555555-5555-4555-8555-555555555555";
    const portraits = [
        "https://cdn.tryblend.ai/first.png",
        "https://cdn.tryblend.ai/second.png",
    ];
    const portraitFile = (url: string) => ({
        id: url,
        name: "portrait.png",
        url,
        size: 0,
        mimeType: "image/png",
        extension: "png",
        mediaCategory: "image",
    });
    for (const workflow of ["fitness", "group_photo"] as const) {
        const parameters =
            workflow === "fitness"
                ? {
                      avatar_request_id: requestId,
                      identity_details: "Pangolin with glasses",
                  }
                : {
                      characters: [
                          {
                              avatar_request_id: requestId,
                              identity_details: "Pangolin with glasses",
                          },
                          {
                              avatar_request_id: secondId,
                              identity_details: "Grey elephant",
                          },
                      ],
                      scene: "Run toward the right",
                  };
        const selected =
            workflow === "fitness"
                ? {
                      workflowId: "fitness-publication",
                      versionId: "fitness-version",
                  }
                : {
                      workflowId: "group-publication",
                      versionId: "group-version",
                  };
        const price = workflow === "fitness" ? 5 : 2;
        const record = requestRecord({
            workflow,
            workflow_version: selected,
            credit_price: price,
        });
        const result = await startAiRun(
            userId,
            createAiRunRequestSchema.parse({ workflow, parameters }),
            key,
            requestDependencies(record, {
                reserve: async (_owner, reservation) => {
                    assert.equal(reservation.workflow, workflow);
                    assert.equal(reservation.creditPrice, price);
                    assert.deepEqual(reservation.version, selected);
                    assert.deepEqual(
                        reservation.sourceRequestIds,
                        workflow === "fitness"
                            ? [requestId]
                            : [requestId, secondId],
                    );
                    return {
                        request: record,
                        shouldStart: true,
                        portraits:
                            workflow === "fitness"
                                ? portraits.slice(0, 1)
                                : portraits,
                    };
                },
                start: async (version, inputs) => {
                    assert.deepEqual(version, selected);
                    assert.deepEqual(
                        inputs,
                        workflow === "fitness"
                            ? {
                                  character_portrait: portraits
                                      .slice(0, 1)
                                      .map(portraitFile),
                                  identity_details: "Pangolin with glasses",
                              }
                            : {
                                  character_portraits:
                                      portraits.map(portraitFile),
                                  scene: "Run toward the right",
                                  cast_roster:
                                      "1. Pangolin with glasses\n2. Grey elephant",
                              },
                    );
                    return {
                        data: { ...selected, runId: "new-run" },
                        rateLimit: {},
                    };
                },
            }),
        );
        assert.equal(result.workflow, workflow);
        assert.equal(result.status, "pending");
    }
});

test("fitness settles only a complete five-image result and group output remains a single image", async () => {
    for (const scenario of [
        "complete",
        "missing",
        "extra_image",
        "unsafe_url",
        "failed_part",
        "group",
    ] as const) {
        const group = scenario === "group";
        const output: Record<string, unknown> = {};
        for (const label of group
            ? ["group_photo"]
            : ["resting", "soft", "average", "fit", "strong"]) {
            output[label] = [
                {
                    id: label,
                    item_index: 0,
                    status: "completed",
                    parts: [
                        {
                            type: "image",
                            url: `https://cdn.tryblend.ai/${label}.png`,
                        },
                    ],
                },
            ];
        }
        if (scenario === "missing") delete output.strong;
        if (scenario === "extra_image")
            output.strong = [
                {
                    id: "strong",
                    item_index: 0,
                    status: "completed",
                    parts: [
                        {
                            type: "image",
                            url: "https://cdn.tryblend.ai/strong.png",
                        },
                        {
                            type: "image",
                            url: "https://cdn.tryblend.ai/extra.png",
                        },
                    ],
                },
            ];
        if (scenario === "unsafe_url")
            output.strong = [
                {
                    id: "strong",
                    item_index: 0,
                    status: "completed",
                    parts: [
                        {
                            type: "image",
                            url: "https://untrusted.example/strong.png",
                        },
                    ],
                },
            ];
        if (scenario === "failed_part")
            output.strong = [
                { id: "strong", item_index: 0, status: "failed", parts: [] },
            ];
        const record = requestRecord({
            workflow: group ? "group_photo" : "fitness",
            status: "pending",
            run_handle: run,
        });
        const provider = await import("@/lib/types/blend/workflow");
        const result = await readAiRun(
            userId,
            requestId,
            requestDependencies(record, {
                read: async () => ({
                    data: provider.blendRunResponseSchema.parse({
                        id: run.runId,
                        status: "completed",
                        output,
                        completed_at: "2026-09-18T12:00:00Z",
                    }),
                    rateLimit: {},
                }),
                finish: async (_owner, _id, _lease, update) => {
                    assert.equal(
                        update.providerCompletedAt,
                        "2026-09-18T12:00:00Z",
                    );
                    assert.equal(
                        update.status,
                        scenario === "complete" || group
                            ? "completed"
                            : "failed",
                    );
                    return requestRecord({
                        ...record,
                        status: update.status,
                        result: update.result,
                        error_code: update.errorCode,
                    });
                },
            }),
        );
        if (result.status === "completed" && result.workflow === "fitness") {
            assert.deepEqual(Object.keys(result.data), [
                "resting",
                "soft",
                "average",
                "fit",
                "strong",
            ]);
        } else if (
            result.status === "completed" &&
            result.workflow === "group_photo"
        ) {
            assert.equal(
                result.data.image_url,
                "https://cdn.tryblend.ai/group_photo.png",
            );
        } else assert.equal(result.status, "failed");
    }
});

test("portrait inputs reject arbitrary URLs, duplicate characters and groups beyond the verified five", () => {
    const character = {
        avatar_request_id: requestId,
        identity_details: "Pangolin",
    };
    for (const invalid of [
        {
            workflow: "fitness",
            parameters: {
                character_portrait: ["https://example.com/image.png"],
                identity_details: "Pangolin",
            },
        },
        {
            workflow: "group_photo",
            parameters: {
                characters: [character, character],
                scene: "Walking",
            },
        },
        {
            workflow: "group_photo",
            parameters: {
                characters: Array.from({ length: 6 }, () => character),
                scene: "Walking",
            },
        },
        {
            workflow: "group_photo",
            parameters: {
                characters: [character],
                scene: "Walking",
                cast_roster: "Client controlled",
            },
        },
    ])
        assert.equal(
            createAiRunRequestSchema.safeParse(invalid).success,
            false,
        );
});

test("unpriced workflows cannot start but their existing actions and status remain recoverable", async () => {
    blendConfiguration.workflows.fitness.creditPrice = undefined;
    try {
        const input = createAiRunRequestSchema.parse({
            workflow: "fitness",
            parameters: {
                avatar_request_id: requestId,
                identity_details: "Pangolin",
            },
        });
        const record = requestRecord({
            workflow: "fitness",
            status: "pending",
            run_handle: run,
            credit_price: 5,
        });
        const result = await startAiRun(
            userId,
            input,
            key,
            requestDependencies(record, {
                reserve: async (_owner, reservation, limits) => {
                    assert.equal(reservation.version, null);
                    assert.equal(reservation.creditPrice, null);
                    assert.equal(limits, null);
                    return { request: record, shouldStart: false };
                },
                start: async () =>
                    assert.fail("Unpriced workflow cannot submit"),
            }),
        );
        assert.equal(result.request_id, requestId);
        assert.equal(
            (await readAiRun(userId, requestId, requestDependencies(record)))
                .status,
            "running",
        );
    } finally {
        blendConfiguration.workflows.fitness.creditPrice = 5;
    }
});

test("the original Avatar publication keeps its original input label", async () => {
    const record = requestRecord({
        workflow_version: { ...version, versionId: legacyAvatarVersionId },
    });
    await startAiRun(
        userId,
        input,
        key,
        requestDependencies(record, {
            start: async (selected, inputs) => {
                assert.equal(selected.versionId, legacyAvatarVersionId);
                assert.deepEqual(inputs, {
                    "variable:prompt:user_request": "A fox with glasses",
                });
                return {
                    data: { ...selected, runId: "old-version-run" },
                    rateLimit: {},
                };
            },
        }),
    );
});

const options = [
    { name: "Street Strutter", line: "Struts like he owns the block. He does." },
    { name: "Lone Wolf", line: "Walks alone. Wins alone." },
    { name: "Night Owl", line: "Late steps still count." },
    { name: "Gym Pigeon", line: "Never skips a crumb or a lap." },
];
const linesOutput = (part: unknown, items = 1) => ({
    options: Array.from({ length: items }, (_, index) => ({
        id: `item-${index}`,
        item_index: index,
        status: "completed",
        parts: [part],
    })),
});

test("companion lines output accepts a JSON part or JSON text, fenced or not, and trims each option", () => {
    const expected = { options };
    for (const part of [
        { type: "json", data: { options } },
        { type: "text", text: JSON.stringify({ options }) },
        { type: "text", text: "```json\n" + JSON.stringify({ options }) + "\n```" },
        { type: "text", text: "```\n" + JSON.stringify({ options }) + "```" },
    ]) {
        assert.deepEqual(blendCompanionLinesOutputSchema.parse(linesOutput(part)), expected);
    }
    const padded = options.map((option) => ({ name: `  ${option.name} `, line: ` ${option.line}  ` }));
    assert.deepEqual(blendCompanionLinesOutputSchema.parse(linesOutput({ type: "json", data: { options: padded } })), expected);
});

test("companion lines output rejects anything but exactly four short single-line options", () => {
    for (const invalid of [
        linesOutput({ type: "json", data: { options: options.slice(0, 3) } }),
        linesOutput({ type: "json", data: { options: [...options, options[0]] } }),
        linesOutput({ type: "json", data: { options: [{ ...options[0], line: "a".repeat(61) }, ...options.slice(1)] } }),
        linesOutput({ type: "json", data: { options: [{ ...options[0], name: "a".repeat(25) }, ...options.slice(1)] } }),
        linesOutput({ type: "json", data: { options: [{ ...options[0], name: "  " }, ...options.slice(1)] } }),
        linesOutput({ type: "json", data: { options: [{ ...options[0], line: "Two\nlines" }, ...options.slice(1)] } }),
        linesOutput({ type: "text", text: "Here are four ideas: Lone Wolf, Night Owl" }),
        linesOutput({ type: "image", url: "https://cdn.tryblend.ai/lines.png" }),
        linesOutput({ type: "json", data: { options } }, 2),
        { result: linesOutput({ type: "json", data: { options } }).options },
    ]) {
        assert.equal(blendCompanionLinesOutputSchema.safeParse(invalid).success, false);
    }
    assert.ok(blendCompanionLinesOutputSchema.safeParse(linesOutput({ type: "json", data: {
        options: [{ name: "a".repeat(24), line: "b".repeat(60) }, ...options.slice(1)],
    } })).success);
});

test("companion lines start sends the chosen portrait, description, language and earlier suggestions to Blend", async () => {
    const portrait = "https://cdn.tryblend.ai/chosen.png";
    const selected = { workflowId: "lines-publication", versionId: "lines-version" };
    const record = requestRecord({ workflow: "companion_lines", workflow_version: selected, credit_price: 0, credit_state: "none" });
    const lines = createAiRunRequestSchema.parse({
        workflow: "companion_lines",
        parameters: {
            avatar_request_id: requestId,
            description: "A grumpy pigeon in a hoodie",
            language: "fr",
            avoid: options.slice(0, 2),
        },
    });
    const result = await startAiRun(userId, lines, key, requestDependencies(record, {
        reserve: async (_owner, reservation) => {
            assert.equal(reservation.workflow, "companion_lines");
            assert.equal(reservation.description, "A grumpy pigeon in a hoodie");
            assert.equal(reservation.creditPrice, 0);
            assert.equal(reservation.resourceId, "33333333-3333-4333-8333-333333333333");
            assert.deepEqual(reservation.sourceRequestIds, [requestId]);
            return { request: record, shouldStart: true, portraits: [portrait] };
        },
        start: async (version, inputs) => {
            assert.deepEqual(version, selected);
            assert.deepEqual(inputs, {
                character_portrait: [{
                    id: portrait,
                    name: "portrait.png",
                    url: portrait,
                    size: 0,
                    mimeType: "image/png",
                    extension: "png",
                    mediaCategory: "image",
                }],
                description: "A grumpy pigeon in a hoodie",
                language: "fr",
                avoid: "Street Strutter: Struts like he owns the block. He does.\nLone Wolf: Walks alone. Wins alone.",
            });
            return { data: { ...selected, runId: "lines-run" }, rateLimit: {} };
        },
    }), "33333333-3333-4333-8333-333333333333");
    assert.equal(result.workflow, "companion_lines");
    assert.equal(result.status, "pending");
    for (const invalid of [
        { ...lines.parameters, language: "de" },
        { ...lines.parameters, avoid: Array.from({ length: 13 }, () => options[0]) },
        { ...lines.parameters, avoid: [{ name: "Max", line: "" }] },
        { ...lines.parameters, extra: true },
    ])
        assert.equal(createAiRunRequestSchema.safeParse({ workflow: "companion_lines", parameters: invalid }).success, false);
});

test("a completed lines run stores its four options; failed, cancelled and unreadable runs keep Blend's raw response", async (t) => {
    const envelope = (status: string, output: unknown) => ({ id: run.runId, status, output, error: { message: "Provider says no" } });
    for (const scenario of ["completed", "failed", "cancelled", "invalid", "failed_item", "unreadable_envelope"] as const) {
        await t.test(scenario, async () => {
            const record = requestRecord({ workflow: "companion_lines", status: "running", run_handle: run, credit_price: 0, credit_state: "none" });
            const output = scenario === "invalid"
                ? linesOutput({ type: "text", text: "not json" })
                : scenario === "failed_item"
                  ? { options: [{ id: "item", item_index: 0, status: "failed", parts: [] }] }
                  : linesOutput({ type: "text", text: JSON.stringify({ options }) });
            const raw = envelope(["failed", "cancelled"].includes(scenario) ? scenario : "completed", output);
            let saved: unknown = "not saved";
            const response = await readAiRun(userId, requestId, requestDependencies(record, {
                read: async () => {
                    if (scenario === "unreadable_envelope")
                        throw new ApiError(502, "ai_invalid_result", "Unreadable", { rateLimit: {}, providerResponse: raw });
                    return {
                        data: blendRunResponseSchema.parse({ ...raw, output: raw.status === "completed" ? output : null }),
                        rateLimit: {},
                        providerResponse: raw,
                    };
                },
                finish: async (_owner, _id, _token, update) => {
                    saved = update.providerResponse;
                    return requestRecord({
                        ...record,
                        status: update.status,
                        result: update.result,
                        error_code: update.errorCode,
                    });
                },
            }));
            if (scenario === "completed") {
                assert.equal(saved, undefined);
                assert.deepEqual(response, { request_id: requestId, workflow: "companion_lines", status: "completed", data: { options } });
            } else {
                assert.deepEqual(saved, raw);
                assert.ok(response.status === "failed" || response.status === "cancelled");
                assert.equal(response.code, {
                    failed: "ai_failed",
                    cancelled: "ai_cancelled",
                    invalid: "ai_invalid_result",
                    failed_item: "ai_failed",
                    unreadable_envelope: "ai_invalid_result",
                }[scenario]);
            }
        });
    }
});

test("a prompt check is free, needs no character, and sends only the description and language to Blend", async () => {
    const selected = { workflowId: "check-publication", versionId: "check-version" };
    const record = requestRecord({ workflow: "prompt_check", workflow_version: selected, credit_price: 0, credit_state: "none" });
    const check = createAiRunRequestSchema.parse({
        workflow: "prompt_check",
        parameters: { description: "  a dog  ", language: "en" },
    });
    const result = await startAiRun(userId, check, key, requestDependencies(record, {
        reserve: async (_owner, reservation) => {
            assert.equal(reservation.workflow, "prompt_check");
            assert.equal(reservation.description, "a dog");
            assert.equal(reservation.creditPrice, 0);
            assert.equal(reservation.resourceId, null);
            assert.deepEqual(reservation.sourceRequestIds, []);
            return { request: record, shouldStart: true, portraits: [] };
        },
        start: async (version, inputs) => {
            assert.deepEqual(version, selected);
            assert.deepEqual(inputs, { description: "a dog", language: "en" });
            return { data: { ...selected, runId: "check-run" }, rateLimit: {} };
        },
    }));
    assert.equal(result.workflow, "prompt_check");
    assert.equal(result.status, "pending");
    for (const invalid of [
        { description: " ", language: "en" },
        { description: "a dog", language: "de" },
        { description: "a".repeat(1001), language: "en" },
        { description: "a dog", language: "en", avatar_request_id: requestId },
    ])
        assert.equal(createAiRunRequestSchema.safeParse({ workflow: "prompt_check", parameters: invalid }).success, false);
});

test("a completed prompt check stores its note and three rewrites; anything else fails as unreadable", async (t) => {
    const variations = ["A red dog.", "A blue dog.", "A gold dog."];
    for (const scenario of ["note", "empty_note", "fenced", "two_variations", "not_json"] as const) {
        await t.test(scenario, async () => {
            const record = requestRecord({ workflow: "prompt_check", status: "running", run_handle: run, credit_price: 0, credit_state: "none" });
            const text = {
                note: JSON.stringify({ note: "What colour is the dog?", variations }),
                empty_note: JSON.stringify({ note: "", variations }),
                fenced: "```json\n" + JSON.stringify({ note: null, variations }) + "\n```",
                two_variations: JSON.stringify({ note: null, variations: variations.slice(0, 2) }),
                not_json: "Sure! Here are some ideas.",
            }[scenario];
            const output = { check: [{ id: "item", item_index: 0, status: "completed", parts: [{ type: "text", text }] }] };
            const response = await readAiRun(userId, requestId, requestDependencies(record, {
                read: async () => ({
                    data: blendRunResponseSchema.parse({ id: run.runId, status: "completed", output }),
                    rateLimit: {},
                    providerResponse: output,
                }),
                finish: async (_owner, _id, _token, update) => requestRecord({
                    ...record,
                    status: update.status,
                    result: update.result,
                    error_code: update.errorCode,
                }),
            }));
            if (scenario === "two_variations" || scenario === "not_json") {
                assert.equal(response.status, "failed");
                assert.equal(response.status === "failed" && response.code, "ai_invalid_result");
            } else {
                assert.deepEqual(response, {
                    request_id: requestId,
                    workflow: "prompt_check",
                    status: "completed",
                    data: { note: scenario === "note" ? "What colour is the dog?" : null, variations },
                });
            }
        });
    }
});

test("a status read that fails keeps Blend's raw response out of the rethrown error detail", async () => {
    const record = requestRecord({ workflow: "companion_lines", status: "running", run_handle: run, credit_price: 0, credit_state: "none" });
    const raw = { id: run.runId, status: "running", output: "SECRET provider detail" };
    await assert.rejects(
        readAiRun(userId, requestId, requestDependencies(record, {
            read: async () => {
                throw new ApiError(502, "ai_status_unavailable", "Unavailable", { rateLimit: {}, providerResponse: raw });
            },
        })),
        (error: unknown) => {
            assert.ok(error instanceof ApiError && error.code === "ai_status_unavailable");
            assert.equal(JSON.stringify(error.detail).includes("SECRET"), false);
            assert.equal(Reflect.get(Object(error.detail), "request_id"), requestId);
            return true;
        },
    );
});

test("a FitFight workflow starts with the request's own fields and owned portraits, never Blend labels", async () => {
    const portrait = "https://cdn.tryblend.ai/portrait.png";
    const cases = [
        {
            input: { workflow: "avatar", parameters: { description: "A fox" } },
            expected: { description: "A fox" },
        },
        {
            input: { workflow: "fitness", parameters: { avatar_request_id: requestId, identity_details: "Green scarf" } },
            expected: { portraits: [portrait], identity_details: "Green scarf" },
        },
        {
            input: {
                workflow: "companion_lines",
                parameters: {
                    avatar_request_id: requestId,
                    description: "A fox",
                    language: "fr",
                    avoid: [{ name: "Rusty", line: "Fast and proud" }],
                },
            },
            expected: { portraits: [portrait], description: "A fox", language: "fr", avoid: "Rusty: Fast and proud" },
        },
        {
            input: { workflow: "prompt_check", parameters: { description: "a dog", language: "en" } },
            expected: { description: "a dog", language: "en" },
        },
        {
            input: { workflow: "group_photo", parameters: {
                characters: [
                    { avatar_request_id: requestId, identity_details: "Green scarf" },
                    { avatar_request_id: "33333333-3333-4333-8333-333333333333", identity_details: "Blue hat" },
                ],
                scene: "On a trail",
            } },
            expected: { portraits: [portrait], scene: "On a trail", cast_roster: "1. Green scarf\n2. Blue hat" },
        },
    ];
    for (const { input, expected } of cases) {
        const parsed = createAiRunRequestSchema.parse(input);
        const selected = { workflowId: `fitfight:${parsed.workflow}`, versionId: "local" };
        const record = requestRecord({ workflow: parsed.workflow, workflow_version: selected, credit_price: 0, credit_state: "none" });
        let started: Record<string, unknown> | null = null;
        await startAiRun(userId, parsed, key, requestDependencies(record, {
            reserve: async () => ({ request: record, shouldStart: true, portraits: parsed.workflow === "prompt_check" ? [] : [portrait] }),
            start: async (version, inputs) => {
                assert.deepEqual(version, selected);
                started = inputs;
                return { data: { ...selected, runId: "wrun_1" }, rateLimit: {} };
            },
        }));
        assert.deepEqual(started, { ...expected, request_id: requestId });
    }
});

test("a FitFight run's return value is the result itself, checked against the workflow's result shape", async (t) => {
    const own = "https://zstzbfocunthczzubggz.supabase.co/storage/v1/object/public/ai-images/wrun_1/step_1.png";
    const handle = { workflowId: "fitfight:avatar", versionId: "local", runId: "wrun_1" };
    const scenarios = {
        own_storage: { output: { image_url: own }, status: "completed" },
        local_host: { output: { image_url: "http://127.0.0.1:54321/storage/v1/object/public/ai-images/a.png" }, status: "failed" },
        blend_envelope: { output: { avatar: [{ id: "a", item_index: 0, status: "completed", parts: [{ type: "image", url: own }] }] }, status: "failed" },
    } as const;
    for (const [name, scenario] of Object.entries(scenarios)) {
        await t.test(name, async () => {
            const record = requestRecord({ status: "running", run_handle: handle });
            const response = await readAiRun(userId, requestId, requestDependencies(record, {
                read: async () => ({ data: { id: "wrun_1", status: "completed", output: scenario.output }, rateLimit: {} }),
                finish: async (_owner, _id, _token, update) => requestRecord({
                    ...record,
                    status: update.status,
                    result: update.result,
                    error_code: update.errorCode,
                }),
            }));
            assert.equal(response.status, scenario.status);
            if (response.status === "completed") assert.deepEqual(response.workflow === "avatar" && response.data, { image_url: own });
            else assert.equal(response.status === "failed" && response.code, "ai_invalid_result");
        });
    }
});
