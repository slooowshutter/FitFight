import { profileCountRowSchema } from "@/lib/types/profiles/shared-profile";
import type { Sql } from "postgres";
import { canDeferFightJoin, fightJoinMemberState } from "@/lib/domain/fights/join-start";
import { ApiError } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { acceptingFightSchema, acceptingInviteSchema } from "@/lib/types/fights/participation-acceptance";
import { joiningMemberRowSchema, joiningSeriesRowSchema } from "@/lib/types/fights/joinable-fight";
import type { FightJoinStart } from "@/lib/types/fights/join-start";
import { ensureAppleHealthSource } from "./apple-health-source-supabase-query";
import { lockFightSeries } from "./fight-series-lock-supabase-query";
import { recalculateFight } from "./recalculate-fight-supabase-query";

/** Token and in-app acceptance commit participation, invitation, and series membership together. */
export async function acceptFightParticipation(
    userId: string, fightId: string, personalTarget: number | undefined, start: FightJoinStart,
    now: Date, tokenHash?: string, database: Sql = createDatabaseClient(), admin = createAdminClient(),
) {
    const source = await ensureAppleHealthSource(userId, { admin });
    await database.begin(async (sql) => {
        await lockFightSeries(sql, fightId);
        const [row] = await sql`select id, state::text, starts_at, ends_at, time_zone, series_id from public.fights where id = ${fightId} for update`;
        if (!row) throw new ApiError(404, "not_found", "Fight not found");
        const fight = acceptingFightSchema.parse(row);
        const [seriesRow] = fight.series_id ? await sql`select id, visibility::text, recurring, paused_at, current_fight_id, join_code from public.fight_series where id = ${fight.series_id}` : [];
        const series = seriesRow ? joiningSeriesRowSchema.parse(seriesRow) : null;
        const [memberRow] = await sql`select state::text from public.fight_members where fight_id = ${fightId} and user_id = ${userId} for update`;
        const member = memberRow ? joiningMemberRowSchema.parse(memberRow) : null;
        if (tokenHash) {
            const [inviteRow] = await sql`select id, fight_id, invited_user_id, expires_at, revoked_at from public.fight_invites where token_hash = ${tokenHash} and fight_id = ${fightId} for update`;
            if (!inviteRow) throw new ApiError(404, "not_found", "Invite not found");
            const invite = acceptingInviteSchema.parse(inviteRow);
            if (invite.revoked_at) throw new ApiError(410, "invite_revoked", "Invite was revoked");
            if (invite.expires_at <= now) throw new ApiError(410, "invite_expired", "Invite expired");
            if (invite.invited_user_id && invite.invited_user_id !== userId) throw new ApiError(403, "invite_wrong_user", "This invite belongs to another user");
        } else if (!member) {
            throw new ApiError(403, "forbidden", "You were not invited to this fight");
        }
        if (["final", "cancelled", "awaiting_final_sync"].includes(fight.state) || fight.ends_at <= now) throw new ApiError(409, "conflict", "Fight is no longer joinable");
        if (member?.state === "accepted" || member?.state === "deferred") return;
        if (!tokenHash && member?.state !== "invited") throw new ApiError(409, "conflict", "This membership cannot be accepted");
        if (series && (series.paused_at || series.current_fight_id !== fightId)) throw new ApiError(409, "conflict", "Fight is no longer joinable");
        const [capacity] = await sql`select count(*)::int n from public.fight_members where fight_id = ${fightId} and state in ('accepted', 'deferred')`;
        if (profileCountRowSchema.parse(capacity).n >= 50) throw new ApiError(409, "fight_full", "This fight is full");
        const state = fightJoinMemberState(start, canDeferFightJoin({
            recurring: series?.recurring ?? false, paused: series?.paused_at != null,
            startsAt: fight.starts_at.toISOString(), timeZone: fight.time_zone, now,
        }));
        if (!state) throw new ApiError(409, "conflict", "This fight does not have a next round to join");
        await sql`
            insert into public.fight_members(fight_id, user_id, state, accepted_at, selected_source_id, source_label, personal_target, target_origin, acceptance_copy_version)
            values (${fightId}, ${userId}, ${state}, ${now}, ${source.id}, ${source.sourceLabel}, ${personalTarget ?? null}, ${personalTarget !== undefined ? "user" : null}, 1)
            on conflict (fight_id, user_id) do update set state = excluded.state, accepted_at = excluded.accepted_at,
                selected_source_id = excluded.selected_source_id, source_label = excluded.source_label,
                personal_target = excluded.personal_target, target_origin = excluded.target_origin, acceptance_copy_version = 1
        `;
        await sql`update public.fight_invites set accepted_at = ${now} where fight_id = ${fightId}
            and (invited_user_id = ${userId} or token_hash = ${tokenHash ?? null}) and accepted_at is null`;
        if (fight.series_id) {
            await sql`insert into public.fight_series_members(series_id, user_id, state, joined_at)
                values (${fight.series_id}, ${userId}, 'accepted', ${now})
                on conflict (series_id, user_id) do update set state = 'accepted', joined_at = excluded.joined_at`;
        }
    });
    await recalculateFight(fightId, now, database);
    const [updated] = await database`select state::text from public.fights where id = ${fightId}`;
    return { id: fightId, state: acceptingFightSchema.shape.state.parse(updated.state) };
}
