import type { Sql } from "postgres";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import type { AiStepRecord } from "@/lib/types/ai/step";

const BUCKET = "ai-images";

/** App-run rows cascade with account deletion; the foreign key also rejects logs from a run that finishes afterward. */
export async function insertAiStep(step: AiStepRecord, database: Sql = createDatabaseClient()) {
    await database`
        insert into private.ai_steps (
            request_id, run_id, workflow, step, step_id, attempt, kind, provider, model, model_used, upstream, status, error,
            started_at, duration_ms, first_token_ms, input_tokens, output_tokens, reasoning_tokens, cached_tokens,
            cost_usd, cost_source, input, output, code_version
        ) values (
            ${step.request_id}, ${step.run_id}, ${step.workflow}, ${step.step}, ${step.step_id}, ${step.attempt}, ${step.kind},
            ${step.provider}, ${step.model}, ${step.model_used}, ${step.upstream}, ${step.status}, ${step.error},
            ${step.started_at}, ${step.duration_ms}, ${step.first_token_ms}, ${step.input_tokens},
            ${step.output_tokens}, ${step.reasoning_tokens}, ${step.cached_tokens}, ${step.cost_usd},
            ${step.cost_source}, ${JSON.stringify(step.input)}::text::jsonb,
            ${step.output === undefined || step.output === null ? null : JSON.stringify(step.output)}::text::jsonb, ${step.code_version}
        )
    `;
}

/**
 * Takes the first region, in the order given, that has started fewer drawings than its limit in the last 60 seconds,
 * records the start and returns its name. Null when every region is full. One lock, so two steps never take the same last slot.
 */
export async function claimAzureImageSlot(
    regions: { name: string; perMinute: number }[],
    runId: string,
    stepId: string,
    database: Sql = createDatabaseClient(),
): Promise<string | null> {
    return database.begin(async (sql) => {
        await sql`select pg_advisory_xact_lock(hashtext('fitfight:azure-image-slots'))`;
        for (const region of regions) {
            const [row] = await sql`
                select count(*)::int as used from private.ai_image_slots
                where region = ${region.name} and created_at > clock_timestamp() - interval '60 seconds'
            `;
            if (Number(row.used) >= region.perMinute) continue;
            await sql`insert into private.ai_image_slots (region, run_id, step_id, created_at)
                values (${region.name}, ${runId}, ${stepId}, clock_timestamp())`;
            return region.name;
        }
        return null;
    });
}

/** The permanent destination can be logged before the upload, so a storage failure cannot hide a paid call. */
export function aiImageLocation(runId: string, stepId: string) {
    const path = `${runId}/${stepId}.png`;
    const url = createAdminClient().storage.from(BUCKET).getPublicUrl(path).data.publicUrl;
    return { path, url };
}

/** Upload retries write the same checkpointed bytes to the same path. */
export async function uploadAiImage(runId: string, stepId: string, png: Uint8Array) {
    const storage = createAdminClient().storage.from(BUCKET);
    const { path, url } = aiImageLocation(runId, stepId);
    const uploaded = await storage.upload(path, png, {
        contentType: "image/png",
        cacheControl: "31536000",
        upsert: true,
    });
    if (uploaded.error) throw uploaded.error;
    return url;
}
