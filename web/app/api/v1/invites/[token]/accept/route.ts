import { z } from "zod";
import { verifyUser } from "@/server/auth/verifyUser";
import { acceptInvite } from "@/server/domain/invites/acceptInvite";
import { apiRoute, corsPreflight, json, readJson } from "@/server/http";

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
