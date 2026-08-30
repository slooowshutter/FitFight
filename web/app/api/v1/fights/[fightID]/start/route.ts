import { z } from "zod";
import { apiRoute, corsPreflight, json, readJson, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { startFight } from "@/lib/supabase/queries/start-fight-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const bodySchema = z.object({
  when: z.enum(["now", "scheduled"]).optional(),
});

export const POST = apiRoute<{ fightID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const fightId = requireUuid(params.fightID, "fightID");
  const body = bodySchema.parse(await readJson(request));
  const fight = await startFight(userId, fightId, body.when ?? "now");
  return json(fight);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
