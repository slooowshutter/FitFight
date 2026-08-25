import { z } from "zod";
import { verifyUser } from "@/server/auth/verifyUser";
import { startFight } from "@/server/domain/fights/startFight";
import { apiRoute, corsPreflight, json, readJson, requireUuid } from "@/server/http";

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
