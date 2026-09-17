import type { FightJoinStart } from "@/lib/types/fights/join-start";
import { acceptFightParticipation } from "./accept-fight-participation-supabase-query";

/** In-app acceptance requires the signed-in user to hold an invited membership. */
export async function acceptMembership(
    userId: string, fightId: string, personalTarget?: number,
    start: FightJoinStart = "now", now: Date = new Date(),
) {
    return acceptFightParticipation(userId, fightId, personalTarget, start, now);
}
