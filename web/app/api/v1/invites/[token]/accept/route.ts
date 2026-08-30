import { z } from "zod";
import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { acceptInvite } from "@/lib/supabase/queries/accept-invite-supabase-query";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const bodySchema = z.object({
  personalTarget: z.number().optional(),
});

export const POST = apiRoute<{ token: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const body = bodySchema.parse(await readJson(request));
  const fight = await acceptInvite(userId, params.token, body.personalTarget);
  return json(fight);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
