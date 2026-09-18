import type { Sql } from "postgres";
import { ApiError } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    loadReadyMedia,
    mapMedia,
    signMediaUrls,
} from "@/lib/supabase/queries/media-supabase-query";
import {
    aiLibraryRowSchema,
    type AiLibraryEntry,
    type SaveAiImages,
} from "@/lib/types/ai/library";
import { aiWorkflowSchema } from "@/lib/types/ai/workflow";

/** Refresh signed media URLs on each account library read. */
export async function readAiLibrary(
    userId: string,
    database: Sql = createDatabaseClient(),
): Promise<AiLibraryEntry[]> {
    const rows = aiLibraryRowSchema.array().parse(
        await database`
        select request_id, workflow, description, stage, media_id
        from private.ai_library_images where user_id = ${userId}
        order by created_at desc, request_id,
            array_position(array['image_url', 'resting', 'soft', 'average', 'fit', 'strong'], stage)
    `,
    );
    if (!rows.length) return [];
    const media = await loadReadyMedia(
        userId,
        rows.map((row) => row.media_id),
        "profile",
        database,
    );
    const urls = await signMediaUrls(media.map((image) => image.object_path));
    const entries = new Map<string, AiLibraryEntry>();
    for (const row of rows) {
        const image = media.find((item) => item.id === row.media_id);
        if (!image) continue;
        const entry: AiLibraryEntry = {
            request_id: row.request_id,
            workflow: row.workflow,
            description: row.description,
            images: [
                {
                    stage: row.stage,
                    media: mapMedia(image, urls.get(image.object_path) ?? null),
                },
            ],
        };
        const existing = entries.get(entry.request_id);
        if (existing) existing.images.push(...entry.images);
        else entries.set(entry.request_id, entry);
    }
    return [...entries.values()].filter(
        (entry) =>
            entry.images.length === (entry.workflow === "fitness" ? 5 : 1),
    );
}

/** Attach already committed, owned uploads atomically. This never starts paid work. */
export async function saveAiImages(
    userId: string,
    requestId: string,
    input: SaveAiImages,
    database: Sql = createDatabaseClient(),
): Promise<void> {
    await database.begin(async (sql) => {
        await sql`select pg_advisory_xact_lock(hashtext(${`ai-library:${requestId}`}))`;
        const existing = aiLibraryRowSchema.array().parse(
            await sql`select request_id, workflow, description, stage, media_id from private.ai_library_images
            where user_id = ${userId} and request_id = ${requestId}`,
        );
        if (existing.length) {
            if (
                existing.length !== input.images.length ||
                existing.some(
                    (row) =>
                        !input.images.some(
                            (image) =>
                                image.stage === row.stage &&
                                image.media_id === row.media_id,
                        ),
                )
            ) {
                throw new ApiError(
                    409,
                    "conflict",
                    "This generation already has saved images.",
                );
            }
            return;
        }
        const [request] = await sql`select workflow from private.ai_requests
            where id = ${requestId} and user_id = ${userId} and status = 'completed' for share`;
        if (!request)
            throw new ApiError(
                404,
                "not_found",
                "Completed generation not found.",
            );
        const workflow = aiWorkflowSchema.parse(request.workflow);
        const expected =
            workflow === "fitness"
                ? ["resting", "soft", "average", "fit", "strong"]
                : ["image_url"];
        if (
            input.images.length !== expected.length ||
            input.images.some((image) => !expected.includes(image.stage))
        ) {
            throw new ApiError(
                400,
                "validation",
                "Save every image from this generation.",
            );
        }
        const media = await sql`select id from public.media_objects
            where owner_id = ${userId} and status = 'ready' and purpose = 'profile' and kind = 'photo'
                and id = any(${sql.array(input.images.map((image) => image.media_id))}::uuid[]) for share`;
        if (media.length !== expected.length)
            throw new ApiError(
                404,
                "not_found",
                "An uploaded image is not available.",
            );
        for (const image of input.images) {
            await sql`insert into private.ai_library_images (request_id, user_id, workflow, description, stage, media_id)
                values (${requestId}, ${userId}, ${workflow}, ${input.description}, ${image.stage}, ${image.media_id})`;
        }
    });
}
