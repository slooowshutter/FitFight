import type { SupabaseClient } from "@supabase/supabase-js";
import {
    isFitFightAdmin,
    readAdminViewer,
} from "@/lib/admin/is-fitfight-admin";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { loadFight } from "./fight-access-supabase-query";
import type { SuggestFightResponse } from "@/lib/types/fights/suggest-fight";

export async function setFightSuggested(
    userId: string,
    fightId: string,
    suggested: boolean,
    admin: SupabaseClient = createAdminClient(),
): Promise<SuggestFightResponse> {
    const viewer = await readAdminViewer(userId, admin);
    if (!isFitFightAdmin(viewer)) {
        throw new ApiError(
            403,
            ERROR_CODES.forbidden,
            "Only Marc can suggest a fight",
        );
    }
    const fight = await loadFight(fightId, admin);
    if (!fight.series_id) {
        throw new ApiError(
            409,
            ERROR_CODES.conflict,
            "This fight cannot be suggested",
        );
    }
    const { error } = await admin
        .from("fight_series")
        .update({
            suggested,
            suggested_at: suggested ? new Date().toISOString() : null,
        })
        .eq("id", fight.series_id);
    if (error) {
        throw new ApiError(
            500,
            ERROR_CODES.db_error,
            "Could not update that suggestion",
        );
    }
    return { suggested };
}
