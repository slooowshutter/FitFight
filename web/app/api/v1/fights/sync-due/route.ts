import { verifyUser } from "@/server/auth/verifyUser";
import { apiRoute, corsPreflight, json } from "@/server/http";
import { closeDueFightsForUser } from "@/server/scoring/closeDueFights";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const result = await closeDueFightsForUser(userId);
  return json(result);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
