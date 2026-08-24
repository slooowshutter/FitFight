import { z } from "zod";
import { verifyUser } from "@/server/auth/verifyUser";
import { acceptMembership } from "@/server/domain/invites/acceptMembership";
import { apiRoute, corsPreflight, json, readJson, requireUuid } from "@/server/http";

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
