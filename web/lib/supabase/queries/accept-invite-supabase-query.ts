import { hashInviteToken } from "@/lib/domain/invites/token";
import { ApiError } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { acceptingInviteSchema } from "@/lib/types/fights/participation-acceptance";
import type { FightJoinStart } from "@/lib/types/fights/join-start";
import { acceptFightParticipation } from "./accept-fight-participation-supabase-query";

export async function acceptInvite(
    userId: string, rawToken: string, personalTarget?: number,
    start: FightJoinStart = "now", now: Date = new Date(),
) {
    const token = decodeURIComponent(rawToken).trim();
    if (!token) throw new ApiError(400, "validation", "Missing invite token");
    const tokenHash = hashInviteToken(token);
    const database = createDatabaseClient();
    const [row] = await database`select fight_id from public.fight_invites where token_hash = ${tokenHash}`;
    if (!row) throw new ApiError(404, "not_found", "Invite not found");
    const fightId = acceptingInviteSchema.shape.fight_id.parse(row.fight_id);
    return acceptFightParticipation(userId, fightId, personalTarget, start, now, tokenHash, database);
}
