import type { Sql } from "postgres";
import { ApiError } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    aiLibraryRowSchema,
    type AiCompanionSelection,
    type AiLibraryEntry,
} from "@/lib/types/ai/library";

export async function readAiLibrary(
    userId: string,
    database: Sql = createDatabaseClient(),
): Promise<AiLibraryEntry[]> {
    const rows = aiLibraryRowSchema.array().parse(
        await database`
        select request_id, workflow, description, stage, image_url
        from private.ai_library_images where user_id = ${userId}
        order by created_at desc, request_id,
            array_position(array['image_url', 'resting', 'soft', 'average', 'fit', 'strong'], stage)
    `,
    );
    const entries = new Map<string, AiLibraryEntry>();
    for (const row of rows) {
        const image = { stage: row.stage, url: row.image_url };
        const entry = entries.get(row.request_id);
        if (entry) entry.images.push(image);
        else
            entries.set(row.request_id, {
                request_id: row.request_id,
                workflow: row.workflow,
                description: row.description,
                images: [image],
            });
    }
    return [...entries.values()];
}

/** The client selects an owned result, never an arbitrary image URL. */
export async function readAiCompanionImage(
    userId: string,
    selection: AiCompanionSelection,
    database: Sql = createDatabaseClient(),
) {
    const [row] = await database`
        select request_id, workflow, description, stage, image_url
        from private.ai_library_images
        where user_id = ${userId} and request_id = ${selection.request_id}
            and stage = ${selection.stage} and workflow in ('avatar', 'fitness')
    `;
    if (!row)
        throw new ApiError(404, "not_found", "Companion image not found.");
    return aiLibraryRowSchema.parse(row);
}
