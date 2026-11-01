import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { runInNewContext } from "node:vm";
import { applySwcTransform } from "@workflow/builders";
import { ModuleKind, ScriptTarget, transpileModule } from "typescript";
import { FatalError } from "workflow";
import { z } from "zod";
import { aiStepRecordSchema, type AiStepRecord } from "@/lib/types/ai/step";

const require = createRequire(import.meta.url);
const sourceFile = fileURLToPath(new URL("./steps.ts", import.meta.url));
const source = readFileSync(sourceFile, "utf8");
const png = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
const requestId = "11111111-1111-4111-8111-111111111111";
const storageRoot = "https://zstzbfocunthczzubggz.supabase.co/storage/v1/object/public/ai-images";

for (const provider of ["azure", "openrouter"]) {
    for (const permanentFailure of [false, true]) {
        test(`${provider} keeps one paid drawing when storage ${permanentFailure ? "exhausts retries" : "fails once"}`, async () => {
            let modelCalls = 0;
            let uploads = 0;
            const logs: AiStepRecord[] = [];
            const costsAtUpload: Array<number | null> = [];
            const uploadedBytes: Uint8Array[] = [];
            const uploadPaths: string[] = [];
            const metadata = { stepId: "", attempt: 1 };
            const registered = new Map<string, ((...args: unknown[]) => Promise<unknown>) & { maxRetries?: number }>();
            const completed = new Map<string, unknown>();
            const stepExports: Record<string, unknown> = {};
            const stepCode = await applySwcTransform("lib/ai/steps.ts", source, "step", sourceFile);
            runInNewContext(transpileModule(stepCode.code, {
                compilerOptions: { module: ModuleKind.CommonJS, target: ScriptTarget.ES2022 },
            }).outputText, {
                exports: stepExports,
                [Symbol.for("@workflow/core//registeredSteps")]: registered,
                Buffer, Uint8Array, Date, Error, URL, FormData, Blob, AbortSignal, performance, console,
                process: { env: provider === "azure" ? { AZURE_IMAGE_SWEDENCENTRAL_API_KEY: "test-only" } : {} },
                fetch: async (url: string) => {
                    if (url === "https://cdn.tryblend.ai/reference.png") return new Response(png);
                    modelCalls++;
                    assert.match(url, provider === "azure" ? /azure\.com\/openai\/v1\/images\/edits/ : /openrouter\.ai\/api\/v1\/images$/);
                    return Response.json({
                        data: [{ b64_json: Buffer.from(png).toString("base64") }],
                        usage: provider === "azure"
                            ? { input_tokens: 100, input_tokens_details: { text_tokens: 50, image_tokens: 50 }, output_tokens: 100 }
                            : { prompt_tokens: 100, completion_tokens: 100, cost: 0.069 },
                    });
                },
                require(specifier: string) {
                    if (specifier === "workflow") return {
                        FatalError,
                        getStepMetadata: () => metadata,
                        getWorkflowMetadata: () => ({ workflowRunId: "run-test", workflowName: "avatar" }),
                    };
                    if (specifier.endsWith("/ai-steps-supabase-query")) return {
                        claimAzureImageSlot: async () => "Sweden Central",
                        insertAiStep: async (record: unknown) => { logs.push(aiStepRecordSchema.parse(record)); },
                        aiImageLocation: (runId: string, stepId: string) => ({
                            path: `${runId}/${stepId}.png`,
                            url: `${storageRoot}/${runId}/${stepId}.png`,
                        }),
                        uploadAiImage: async (runId: string, stepId: string, bytes: Uint8Array) => {
                            uploads++;
                            uploadedBytes.push(new Uint8Array(bytes));
                            uploadPaths.push(`${runId}/${stepId}.png`);
                            costsAtUpload.push(logs.at(-1)?.cost_usd ?? null);
                            if (permanentFailure || uploads === 1) throw new Error("Storage temporarily unavailable");
                            return `${storageRoot}/${runId}/${stepId}.png`;
                        },
                    };
                    return require(specifier);
                },
            });

            // Use the SDK compiler's real step boundaries; only its scheduler and external services are replaced.
            const workflowExports: Record<string, unknown> = {};
            const workflowCode = await applySwcTransform("lib/ai/steps.ts", source, "workflow", sourceFile);
            runInNewContext(transpileModule(workflowCode.code, {
                compilerOptions: { module: ModuleKind.CommonJS, target: ScriptTarget.ES2022 },
            }).outputText, {
                exports: workflowExports,
                [Symbol.for("WORKFLOW_USE_STEP")]: (id: string) => async (...args: unknown[]) => {
                    if (completed.has(id)) return structuredClone(completed.get(id));
                    const step = registered.get(id);
                    assert.ok(step, `Missing compiled step ${id}`);
                    for (let attempt = 1; ; attempt++) {
                        metadata.stepId = id;
                        metadata.attempt = attempt;
                        try {
                            const result = await step(...structuredClone(args));
                            completed.set(id, structuredClone(result));
                            return structuredClone(result);
                        } catch (error) {
                            if (error instanceof FatalError || attempt > (step.maxRetries ?? 3)) throw error;
                        }
                    }
                },
            });
            const image = z.function().parse(workflowExports.image);
            const result = image({
                requestId,
                name: "Draw the avatar", model: "openai/gpt-image-2.5-sunburst",
                prompt: "A fox", images: ["https://cdn.tryblend.ai/reference.png"], size: "1024x1024",
            });
            if (permanentFailure) await assert.rejects(Promise.resolve(result), /Storage temporarily unavailable/);
            else assert.match(z.string().parse(await result), /^https:\/\/zstzbfocunthczzubggz\.supabase\.co\//);

            assert.equal(modelCalls, 1, "An upload retry must not call the paid model again");
            assert.equal(uploads, permanentFailure ? 4 : 2);
            assert.equal(logs.length, 1, "One model call must have exactly one accounting row");
            assert.equal(logs[0].request_id, requestId);
            assert.equal(logs[0].status, "completed");
            assert.equal(logs[0].cost_usd, provider === "azure" ? 0.00365 : 0.069);
            assert.ok(costsAtUpload.every((cost) => cost === logs[0].cost_usd), "Record the charge before storage can fail");
            assert.ok(uploadPaths.every((path) => path === uploadPaths[0]));
            for (const bytes of uploadedBytes) assert.deepEqual(bytes, png);
        });
    }
}
