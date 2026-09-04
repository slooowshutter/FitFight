import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { leaveFight } from "@/lib/supabase/queries/leave-fight-supabase-query";
import { leaveFightRequestSchema } from "@/lib/types/fights/joinable-fight";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const parsed = leaveFightRequestSchema.safeParse(await readJson(request));
  if (!parsed.success) {
    throw parsed.error;
  }
  const fight = await leaveFight(userId, parsed.data.fightId);
  return json(fight);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
