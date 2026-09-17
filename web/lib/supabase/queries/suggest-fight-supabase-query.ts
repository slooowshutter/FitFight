import type { SupabaseClient } from "@supabase/supabase-js";
import type { Sql } from "postgres";
import { isFitFightAdmin } from "@/lib/admin/is-fitfight-admin";
import { readAdminViewer } from "@/lib/supabase/queries/auth-supabase-query";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import type { FightSeriesRow } from "@/lib/types/database";
import type { SuggestFightResponse } from "@/lib/types/fights/suggest-fight";
import { inviteEveryoneToOpenFight } from "./app-wide-fight-invite-supabase-query";
import { currentJoinableFight } from "./join-fight-supabase-query";
import { loadFight } from "./fight-access-supabase-query";
import { enqueueFightInviteNotifications } from "./notification-intents-supabase-query";

export async function setFightSuggested(
    userId: string,
    fightId: string,
    suggested: boolean,
    admin: SupabaseClient = createAdminClient(),
    sql: Sql = createDatabaseClient(),
    now: Date = new Date(),
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
    const { data: seriesData, error: seriesError } = await admin
        .from("fight_series")
        .select("*")
        .eq("id", fight.series_id)
        .maybeSingle();
    if (seriesError || !seriesData) {
        throw new ApiError(500, ERROR_CODES.db_error, "Could not load series");
    }
    const series = seriesData as FightSeriesRow;
    const wasSuggested = series.suggested;
    const { error } = await admin
        .from("fight_series")
        .update({
            suggested,
            suggested_at: suggested ? now.toISOString() : null,
        })
        .eq("id", fight.series_id);
    if (error) {
        throw new ApiError(
            500,
            ERROR_CODES.db_error,
            "Could not update that suggestion",
        );
    }
    if (suggested && !wasSuggested) {
        const current = await currentJoinableFight(series, admin, now);
        if (current) {
            const invitedIds = await inviteEveryoneToOpenFight(
                series,
                current,
                sql,
            );
            if (invitedIds.length > 0) {
                const { data: owner } = await admin
                    .from("profiles")
                    .select("handle, display_name")
                    .eq("user_id", series.owner_id)
                    .maybeSingle();
                const display = owner?.display_name?.replace(/\s+/g, " ").trim();
                await enqueueFightInviteNotifications(sql, {
                    fightId: current.id,
                    fightName: series.name,
                    actorName:
                        display && display.length > 0
                            ? display
                            : (owner?.handle ?? "user"),
                    userIds: invitedIds,
                    now,
                });
            }
        }
    }
    return { suggested };
}
