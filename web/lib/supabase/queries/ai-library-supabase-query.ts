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
        select library.request_id, library.workflow, library.description, library.stage, library.image_url
        from private.ai_library_images library
        left join private.ai_requests request on request.id = library.request_id
        left join private.custom_character_purchases purchase on purchase.id = request.resource_id
        where library.user_id = ${userId} and purchase.revoked_at is null
        order by library.created_at desc, library.request_id,
            array_position(array['image_url', 'resting', 'soft', 'average', 'fit', 'strong'], library.stage)
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
        select library.request_id, library.workflow, library.description, library.stage, library.image_url
        from private.ai_library_images library
        left join private.ai_requests request on request.id = library.request_id
        left join private.custom_character_purchases purchase on purchase.id = request.resource_id
        where library.user_id = ${userId} and library.request_id = ${selection.request_id}
            and library.stage = ${selection.stage} and library.workflow in ('avatar', 'fitness')
            and purchase.revoked_at is null
    `;
    if (!row)
        throw new ApiError(404, "not_found", "Companion image not found.");
    return aiLibraryRowSchema.parse(row);
}
