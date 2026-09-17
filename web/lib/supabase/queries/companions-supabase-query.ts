import type { Sql } from "postgres";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    savedCompanionPromptsSchema,
    type SavedCompanionPrompts,
} from "@/lib/types/companions/companion";

/** Only the authenticated owner's private descriptions belong in this response. */
export async function readCompanionPrompts(
    userId: string,
    database: Sql = createDatabaseClient(),
): Promise<SavedCompanionPrompts> {
    const rows = await database`
        select library.prompts from private.companion_libraries as library
        join public.profiles as profile on profile.user_id = library.user_id
        where library.user_id = ${userId} and profile.deleted_at is null
    `;
    return savedCompanionPromptsSchema.parse(rows.length ? rows[0].prompts : []);
}
