import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { membershipDecisionRowSchema } from "@/lib/types/fights/membership-decision";

export async function declineMembership(
  userId: string,
  fightId: string,
  database: Sql = createDatabaseClient(),
) {
  return database.begin("read write", async (sql) => {
    const rows = await sql`
      select fight.id, fight.state::text as state, member.state::text as member_state
      from public.fights as fight
      join public.fight_members as member on member.fight_id = fight.id
      where fight.id = ${fightId} and member.user_id = ${userId}
      for update of fight, member
    `;
    if (!rows[0]) {
      throw new ApiError(403, ERROR_CODES.forbidden, "You were not invited to this fight");
    }
    const fight = membershipDecisionRowSchema.parse(rows[0]);
    if (fight.member_state === "declined") {
      return { id: fight.id, state: fight.state };
    }
    if (fight.member_state !== "invited" || ["final", "cancelled"].includes(fight.state)) {
      throw new ApiError(409, ERROR_CODES.conflict, "This membership cannot be declined");
    }
    await sql`
      update public.fight_members set state = 'declined'
      where fight_id = ${fightId} and user_id = ${userId}
    `;
    await sql`
      update public.fight_invites set revoked_at = now()
      where fight_id = ${fightId} and invited_user_id = ${userId}
        and revoked_at is null
    `;
    return { id: fight.id, state: fight.state };
  });
}
