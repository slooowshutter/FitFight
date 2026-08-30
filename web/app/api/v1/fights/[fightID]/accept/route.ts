import { z } from "zod";
import { apiRoute, corsPreflight, json, readJson, requireUuid } from "@/lib/http";
import { acceptMembership } from "@/lib/supabase/queries/accept-membership-supabase-query";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const bodySchema = z.object({
  personalTarget: z.number().optional(),
});

export const POST = apiRoute<{ fightID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const fightId = requireUuid(params.fightID, "fightID");
  const body = bodySchema.parse(await readJson(request));
  const fight = await acceptMembership(userId, fightId, body.personalTarget);
  return json(fight);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
