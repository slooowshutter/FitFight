import type { Sql } from "postgres";
import { ApiError } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { departureFightSchema, departureMemberSchema } from "@/lib/types/fights/membership-departure";

/** The capture trigger records the cause in the same transaction as the membership change. */
export async function departFightMemberships(actorId: string, fightId: string, targetId: string, database: Sql = createDatabaseClient()) {
    return database.begin(async (sql) => {
        const fights = departureFightSchema.array().parse(await sql`
            select id, owner_id, state::text, series_id from public.fights
            where id = ${fightId} or id = (
                select series.current_fight_id from public.fights original
                join public.fight_series series on series.id = original.series_id where original.id = ${fightId}
            ) order by id for update
        `);
        const fight = fights.find((item) => item.id === fightId);
        if (!fight) throw new ApiError(404, "not_found", "Fight not found");
        const voluntary = actorId === targetId;
        if (voluntary && fight.owner_id === actorId) throw new ApiError(403, "forbidden", "The owner cannot leave this fight");
        if (!voluntary && (fight.owner_id !== actorId || targetId === fight.owner_id)) throw new ApiError(403, "forbidden", "Only the owner can remove another participant");
        if (!voluntary && ["final", "cancelled", "awaiting_final_sync"].includes(fight.state)) throw new ApiError(409, "conflict", "This fight can no longer be edited");
        const members = departureMemberSchema.array().parse(await sql`
            select fight_id, state::text from public.fight_members where user_id = ${targetId}
                and fight_id = any(${sql.array(fights.map((item) => item.id))}::uuid[]) order by fight_id for update
        `);
        const original = members.find((member) => member.fight_id === fightId);
        if (voluntary && !original) throw new ApiError(403, "forbidden", "You are not in this fight");
        if (voluntary && original && !["accepted", "deferred", "withdrawn"].includes(original.state)) throw new ApiError(409, "conflict", "This membership cannot be left");
        await sql`select set_config('fitfight.membership_departure', ${voluntary ? "voluntary" : "removed"}, true)`;
        const active = members.filter((member) => member.state === "accepted" || member.state === "deferred" || (!voluntary && member.state === "invited"));
        if (active.length > 0) {
            await sql`update public.fight_members set state = 'withdrawn' where user_id = ${targetId}
                and fight_id = any(${sql.array(active.map((member) => member.fight_id))}::uuid[])`;
            if (!voluntary) {
                await sql`update public.fight_invites set revoked_at = coalesce(revoked_at, now())
                    where invited_user_id = ${targetId} and fight_id = any(${sql.array(active.map((member) => member.fight_id))}::uuid[])`;
            }
        }
        if (fight.series_id) {
            await sql`update public.fight_series_members set state = 'withdrawn' where series_id = ${fight.series_id} and user_id = ${targetId}`;
        }
        return { fight, changed: active.map((member) => member.fight_id) };
    });
}
