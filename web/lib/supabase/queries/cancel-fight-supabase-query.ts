import type { SupabaseClient } from "@supabase/supabase-js";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { fightSummary, loadOwnedFight } from "./fight-access-supabase-query";

export async function cancelFight(
    userId: string,
    fightId: string,
    admin: SupabaseClient = createAdminClient(),
    now: Date = new Date(),
) {
    const fight = await loadOwnedFight(fightId, userId, admin);

    switch (fight.state) {
        case "final":
            throw new ApiError(
                409,
                ERROR_CODES.fight_not_cancellable,
                "Final fights cannot be cancelled",
            );
        case "cancelled":
        case "draft":
        case "inviting":
        case "scheduled":
        case "live":
        case "awaiting_final_sync":
            break;
        default: {
            const _exhaustive: never = fight.state;
            throw new ApiError(
                409,
                ERROR_CODES.fight_not_cancellable,
                "Final fights cannot be cancelled",
            );
        }
    }

    await pauseFightSeries(admin, fight.series_id, now);
    if (fight.state === "cancelled") {
        return fightSummary(fight);
    }

    const { data: updated, error } = await admin
        .from("fights")
        .update({ state: "cancelled" })
        .eq("id", fightId)
        .select("id, state")
        .single();
    if (error || !updated) {
        throw new ApiError(500, ERROR_CODES.db_error, "Could not cancel fight");
    }

    return fightSummary(updated);
}

async function pauseFightSeries(
    admin: SupabaseClient,
    seriesId: string | null,
    now: Date,
) {
    if (!seriesId) {
        return;
    }
    const { error } = await admin
        .from("fight_series")
        .update({ paused_at: now.toISOString() })
        .eq("id", seriesId)
        .is("paused_at", null);
    if (error) {
        throw new ApiError(500, ERROR_CODES.db_error, "Could not cancel fight");
    }
}
