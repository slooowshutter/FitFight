import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { test } from "node:test";
import { runInNewContext } from "node:vm";
import { createOpenRouter } from "@openrouter/ai-sdk-provider";
import { APICallError } from "ai";
import { ModuleKind, ScriptTarget, transpileModule } from "typescript";
import { FatalError } from "workflow";
import { aiStepRecordSchema, openRouterStreamErrorSchema, type AiStepRecord } from "@/lib/types/ai/step";

const require = createRequire(import.meta.url);
const requestId = "11111111-1111-4111-8111-111111111111";
const { outputText } = transpileModule(readFileSync(new URL("./steps.ts", import.meta.url), "utf8"), {
    compilerOptions: { module: ModuleKind.CommonJS, target: ScriptTarget.ES2022 },
});

for (const scenario of [
    { code: 400, fatal: true, streamed: true },
    { code: "403", fatal: true, streamed: true },
    { code: 408, fatal: false, streamed: true },
    { code: "429", fatal: false, streamed: true },
    { code: 500, fatal: false, streamed: true },
    { code: "503", fatal: false, streamed: true },
    { code: 400, fatal: true, streamed: false },
    { code: 403, fatal: true, streamed: false },
    { code: 408, fatal: false, streamed: false },
    { code: 429, fatal: false, streamed: false },
    { code: 500, fatal: false, streamed: false },
]) {
    test(`text steps ${scenario.fatal ? "stop" : "remain retryable"} after ${scenario.streamed ? "streamed" : "HTTP"} ${scenario.code} errors`, async () => {
        const message = `Provider error ${scenario.code}`;
        const logs: AiStepRecord[] = [];
        const exports: Record<string, unknown> = {};
        let calls = 0;
        runInNewContext(outputText, {
            exports,
            Date,
            Error,
            URL,
            AbortSignal,
            performance,
            console,
            process: { env: { AI_WORKFLOWS_OPENROUTER_API_KEY: "test-only-key" } },
            require(specifier: string) {
                if (specifier === "@openrouter/ai-sdk-provider") return {
                    createOpenRouter: (options: Parameters<typeof createOpenRouter>[0]) => createOpenRouter({
                        ...options,
                        fetch: async () => {
                            calls++;
                            if (!scenario.streamed) return Response.json(
                                { error: { code: scenario.code, message } },
                                { status: Number(scenario.code) },
                            );
                            return new Response([
                                `data: ${JSON.stringify({ id: "reply", model: "test-model", choices: [{ index: 0, delta: { content: "Partial answer" }, finish_reason: null }] })}`,
                                `data: ${JSON.stringify({ error: { code: scenario.code, message } })}`,
                                "data: [DONE]",
                                "",
                            ].join("\n\n"), { headers: { "Content-Type": "text/event-stream" } });
                        },
                    }),
                };
                if (specifier === "workflow") return {
                    FatalError,
                    getWorkflowMetadata: () => ({ workflowRunId: "run-test", workflowName: "workflow//promptCheck" }),
                    getStepMetadata: () => ({ stepId: "step-test", attempt: 1 }),
                };
                if (specifier.endsWith("/ai-steps-supabase-query")) return {
                    insertAiStep: async (step: unknown) => { logs.push(aiStepRecordSchema.parse(step)); },
                };
                return require(specifier);
            },
        });
        assert.ok(typeof exports.text === "function");
        await assert.rejects(exports.text({ requestId, name: "Check the description", model: "test-model", prompt: "A fox" }), (error: unknown) => {
            assert.equal(error instanceof FatalError, scenario.fatal);
            if (scenario.fatal) {
                assert.ok(error instanceof Error);
                assert.equal(error.message, message);
            } else if (scenario.streamed) {
                assert.equal(openRouterStreamErrorSchema.parse(error).code, Number(scenario.code));
            } else {
                assert.ok(APICallError.isInstance(error));
                assert.equal(error.statusCode, Number(scenario.code));
            }
            return true;
        });
        assert.equal(calls, 1);
        assert.equal(logs.length, 1);
        assert.equal(logs[0].request_id, requestId);
        assert.equal(logs[0].status, "failed");
        assert.equal(logs[0].error, message);
        assert.equal(logs[0].output, null);
    });
}
