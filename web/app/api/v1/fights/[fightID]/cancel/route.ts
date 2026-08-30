import { apiRoute, corsPreflight, json, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { cancelFight } from "@/lib/supabase/queries/cancel-fight-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute<{ fightID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const fightId = requireUuid(params.fightID, "fightID");
  const fight = await cancelFight(userId, fightId);
  return json(fight);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
