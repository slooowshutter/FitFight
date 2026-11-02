import { createOpenRouter } from "@openrouter/ai-sdk-provider";
import { APICallError, streamText } from "ai";
import { FatalError, getStepMetadata, getWorkflowMetadata } from "workflow";
import { aiImageLocation, claimAzureImageSlot, insertAiStep, uploadAiImage } from "@/lib/supabase/queries/ai-steps-supabase-query";
import { aiImageUrlSchema } from "@/lib/types/ai/workflow";
import {
    azureImageRegions,
    azureImageResponseSchema,
    openRouterImageResponseSchema,
    openRouterStreamErrorSchema,
    openRouterUsageSchema,
    sunburstListPrice,
    type AiDrawnImage,
    type AiImageStep,
    type AiStepRecord,
    type AiTextStep,
} from "@/lib/types/ai/step";

// The model calls every workflow in web/lib/ai/workflows.ts is made of: text through OpenRouter, drawings on Azure
// first. Model calls and picture uploads are separate Workflow SDK steps, so an upload retry reuses the saved drawing.
// Each model attempt writes one row to private.ai_steps: what went in, what came out, how long it took,
// the tokens and the cost. App-run rows follow account deletion; otherwise they are kept forever.

const OPENROUTER_URL = "https://openrouter.ai/api/v1";
const HEADERS = { "HTTP-Referer": "https://fitfight.app", "X-Title": "FitFight" };

/** Puts each {{name}} value in, then trims, as Blend did. A name with no value stays as written. */
function fill(template: string, vars: Record<string, string> = {}) {
    return template.replace(/\{\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}\}/g, (match, name: string) => vars[name] ?? match).trim();
}

async function log(
    step: Pick<AiStepRecord, "request_id" | "step" | "kind" | "model" | "input"> & Partial<Pick<AiStepRecord, "provider" | "upstream">>,
    startedAt: Date,
    started: number,
    result: Partial<AiStepRecord>,
) {
    const workflow = getWorkflowMetadata();
    const meta = getStepMetadata();
    try {
        await insertAiStep({
            run_id: workflow.workflowRunId,
            workflow: workflow.workflowName.split("//").pop() ?? workflow.workflowName,
            step_id: meta.stepId,
            attempt: meta.attempt,
            provider: "openrouter",
            started_at: startedAt,
            duration_ms: Math.round(performance.now() - started),
            model_used: null,
            upstream: null,
            status: "completed",
            error: null,
            first_token_ms: null,
            input_tokens: null,
            output_tokens: null,
            reasoning_tokens: null,
            cached_tokens: null,
            cost_usd: null,
            cost_source: null,
            output: null,
            code_version: process.env.VERCEL_GIT_COMMIT_SHA ?? "local",
            ...step,
            ...result,
        });
    } catch (error) {
        // NOTE: the model call is done and paid for; a lost log row must not make the step run it again.
        console.error("fitfight_ai_step_log_failed", workflow.workflowRunId, error);
    }
}

/** Logs a failed attempt. A refused or invalid request fails the same way every time, so it is not retried. */
async function fail(step: Parameters<typeof log>[0], startedAt: Date, started: number, error: unknown, status?: number) {
    // OpenRouter's error inside a stream is a plain object, not an Error.
    const streamed = openRouterStreamErrorSchema.safeParse(error);
    const message = (streamed.success ? streamed.data.message : error instanceof Error ? error.message : JSON.stringify(error)).slice(0, 2000);
    await log(step, startedAt, started, { status: "failed", error: message });
    const code = status ?? (APICallError.isInstance(error) ? error.statusCode : streamed.success ? streamed.data.code : undefined);
    return code !== undefined && code >= 400 && code < 500 && code !== 408 && code !== 429 ? new FatalError(message) : error;
}

/** One text or vision call. Returns the model's text, trimmed. */
export async function text(step: AiTextStep): Promise<string> {
    "use step";
    const startedAt = new Date();
    const started = performance.now();
    const system = step.system === undefined ? undefined : fill(step.system, step.vars);
    const prompt = fill(step.prompt, step.vars);
    const images = step.images ?? [];
    const logged = {
        request_id: step.requestId,
        step: step.name,
        kind: "text" as const,
        model: step.model,
        input: { system, prompt, images, temperature: step.temperature, reasoning: step.reasoning },
    };
    let firstToken: number | null = null;
    // NOTE: a failed stream only says "No output generated"; the provider's error arrives here.
    let streamError: unknown;
    try {
        const openrouter = createOpenRouter({ apiKey: process.env.AI_WORKFLOWS_OPENROUTER_API_KEY, headers: HEADERS });
        const result = streamText({
            model: openrouter(step.model, {
                usage: { include: true },
                ...(step.reasoning ? { reasoning: { effort: step.reasoning } } : {}),
            }),
            system,
            temperature: step.temperature,
            messages: [{
                role: "user",
                content: [
                    { type: "text", text: prompt },
                    ...images.map((url) => ({ type: "image" as const, image: new URL(url), mediaType: "image/png" })),
                ],
            }],
            // Picture links go to OpenRouter as they are, as Blend sent them; the SDK would download most of them.
            experimental_download: async (requested) => requested.map(() => null),
            maxRetries: 0,
            abortSignal: AbortSignal.timeout(180_000),
            onChunk: ({ chunk }) => {
                if (chunk.type === "text-delta" || chunk.type === "reasoning-delta")
                    firstToken ??= Math.round(performance.now() - started);
            },
            onError: ({ error }) => {
                streamError = error;
            },
        });
        const output = (await result.text).trim();
        // NOTE: an error in the middle of the stream still ends with the partial text; it must not count as an answer.
        if (streamError !== undefined) throw streamError;
        if (!output) throw new Error("The model returned no text");
        const usage = await result.usage;
        const meta = (await result.providerMetadata)?.openrouter;
        const accounting = openRouterUsageSchema.safeParse(meta?.usage);
        await log(logged, startedAt, started, {
            output,
            first_token_ms: firstToken,
            model_used: (await result.response).modelId,
            upstream: typeof meta?.provider === "string" ? meta.provider : null,
            input_tokens: usage.inputTokens ?? null,
            output_tokens: usage.outputTokens ?? null,
            reasoning_tokens: usage.outputTokenDetails?.reasoningTokens ?? null,
            cached_tokens: usage.inputTokenDetails?.cacheReadTokens ?? null,
            cost_usd: accounting.success ? accounting.data.cost : null,
            cost_source: accounting.success ? "provider" : null,
        });
        return output;
    } catch (error) {
        throw await fail(logged, startedAt, started, streamError ?? error);
    }
}

/** A text call whose answer is JSON, optionally in a ```json fence. A reply that is not JSON is asked again. */
export async function json(step: AiTextStep): Promise<unknown> {
    "use step";
    const reply = await text(step);
    const fenced = /^```(?:json)?\s*([\s\S]*?)\s*```$/.exec(reply);
    return JSON.parse(fenced ? fenced[1] : reply);
}

/**
 * One transparent PNG drawing, saved to FitFight's storage. Returns the picture's permanent link. Sunburst draws on
 * Azure first, paid with credits: a random region with a free slot this minute, then the next one when a region is
 * busy or down. OpenRouter draws only when every region is full or has failed. Each attempt writes its own row.
 */
export async function image(step: AiImageStep): Promise<string> {
    const drawn = await drawImage(step);
    return saveImage(drawn);
}

// NOTE: This boundary checkpoints the paid image bytes before any storage upload can fail.
async function drawImage(step: AiImageStep): Promise<AiDrawnImage> {
    "use step";
    const prompt = fill(step.prompt, step.vars);
    const settings = { size: step.size, quality: "high", background: "transparent", output_format: "png" } as const;
    const { workflowRunId } = getWorkflowMetadata();
    const { stepId } = getStepMetadata();
    const { url } = aiImageLocation(workflowRunId, stepId);
    const regions = step.model === "openai/gpt-image-2.5-sunburst" ? azureImageRegions.filter((region) => process.env[region.keyEnv]) : [];
    const tried = new Set<string>();
    for (;;) {
        const untried = regions.filter((region) => !tried.has(region.name)).sort(() => Math.random() - 0.5);
        const claimed = untried.length > 0 ? await claimAzureImageSlot(untried, workflowRunId, stepId) : null;
        const region = untried.find((candidate) => candidate.name === claimed);
        if (region === undefined) break;
        tried.add(region.name);
        const startedAt = new Date();
        const started = performance.now();
        const logged = {
            request_id: step.requestId,
            step: step.name, kind: "image" as const, model: step.model, provider: "azure" as const, upstream: `Azure ${region.name}`,
            input: { prompt, images: step.images, ...settings },
        };
        let status: number | undefined;
        try {
            const form = new FormData();
            for (const [name, value] of Object.entries({ model: "gpt-image-2.5-sunburst", prompt, ...settings })) form.append(name, value);
            for (const url of step.images) {
                // Only Blend's and FitFight's storage, never a redirect: the server must not fetch an arbitrary address.
                if (!aiImageUrlSchema.safeParse(url).success) throw new FatalError(`Input picture outside the allowed storage: ${url}`);
                const picture = await fetch(url, { redirect: "error", signal: AbortSignal.timeout(30_000) });
                if (!picture.ok) throw new Error(`Input picture ${picture.status}: ${url}`);
                form.append("image[]", new Blob([await picture.arrayBuffer()], { type: "image/png" }), "image.png");
            }
            const response = await fetch(`${region.endpoint}/images/edits?api-version=preview`, {
                method: "POST",
                headers: { "api-key": process.env[region.keyEnv] ?? "" },
                body: form,
                signal: AbortSignal.timeout(280_000),
            });
            status = response.status;
            if (!response.ok) throw new Error(`Azure ${region.name} ${response.status}: ${(await response.text()).slice(0, 1000)}`);
            const drawn = azureImageResponseSchema.parse(await response.json());
            const png = new Uint8Array(Buffer.from(drawn.data[0].b64_json, "base64"));
            const usage = drawn.usage;
            await log(logged, startedAt, started, {
                output: url,
                model_used: "gpt-image-2.5-sunburst",
                input_tokens: usage?.input_tokens ?? null,
                output_tokens: usage?.output_tokens ?? null,
                cost_usd: usage
                    ? (usage.input_tokens_details.text_tokens * sunburstListPrice.textInput
                        + usage.input_tokens_details.image_tokens * sunburstListPrice.imageInput
                        + usage.output_tokens * sunburstListPrice.output) / 1_000_000
                    : null,
                cost_source: usage ? "price_list" : null,
            });
            return { png, runId: workflowRunId, stepId };
        } catch (error) {
            const failed = await fail(logged, startedAt, started, error, status);
            // Like Blend: a busy, missing or broken region passes the drawing to the next; a refusal stops it.
            if (error instanceof FatalError || (status !== undefined && ![404, 408, 429, 500, 502, 503, 504].includes(status))) throw failed;
        }
    }
    const startedAt = new Date();
    const started = performance.now();
    // NOTE: this calls OpenRouter directly: the AI SDK's image call drops the cost OpenRouter reports.
    const body = {
        model: step.model,
        prompt,
        ...settings,
        input_references: step.images.map((url) => ({ type: "image_url", image_url: { url } })),
    };
    const logged = { request_id: step.requestId, step: step.name, kind: "image" as const, model: step.model, input: body };
    let status: number | undefined;
    try {
        const response = await fetch(`${OPENROUTER_URL}/images`, {
            method: "POST",
            headers: { ...HEADERS, Authorization: `Bearer ${process.env.AI_WORKFLOWS_OPENROUTER_API_KEY}`, "Content-Type": "application/json" },
            body: JSON.stringify(body),
            signal: AbortSignal.timeout(280_000),
        });
        status = response.status;
        if (!response.ok) throw new Error(`OpenRouter image ${response.status}: ${(await response.text()).slice(0, 1000)}`);
        const drawn = openRouterImageResponseSchema.parse(await response.json());
        const png = new Uint8Array(Buffer.from(drawn.data[0].b64_json, "base64"));
        await log(logged, startedAt, started, {
            output: url,
            model_used: drawn.model ?? null,
            upstream: drawn.provider ?? null,
            input_tokens: drawn.usage?.prompt_tokens ?? null,
            output_tokens: drawn.usage?.completion_tokens ?? null,
            cost_usd: drawn.usage?.cost ?? null,
            cost_source: drawn.usage?.cost == null ? null : "provider",
        });
        return { png, runId: workflowRunId, stepId };
    } catch (error) {
        throw await fail(logged, startedAt, started, error, status);
    }
}
// A drawing is retried once: each attempt is paid, and most failures a second try fixes are timeouts.
drawImage.maxRetries = 1;

async function saveImage(drawn: AiDrawnImage): Promise<string> {
    "use step";
    return uploadAiImage(drawn.runId, drawn.stepId, drawn.png);
}
