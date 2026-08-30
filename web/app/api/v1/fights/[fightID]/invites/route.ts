import { z } from "zod";
import { apiRoute, corsPreflight, json, readJson, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { createInvite } from "@/lib/supabase/queries/create-invite-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const bodySchema = z.object({
  handle: z.string().min(1),
});

export const POST = apiRoute<{ fightID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const fightId = requireUuid(params.fightID, "fightID");
  const { handle } = bodySchema.parse(await readJson(request));
  const invite = await createInvite(userId, fightId, handle);
  return json(invite);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
