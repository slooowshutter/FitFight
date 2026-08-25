import { verifyUser } from "@/server/auth/verifyUser";
import { cancelFight } from "@/server/domain/fights/cancelFight";
import { apiRoute, corsPreflight, json, requireUuid } from "@/server/http";

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
