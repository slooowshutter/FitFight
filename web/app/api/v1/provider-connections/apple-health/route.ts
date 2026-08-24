import { verifyUser } from "@/server/auth/verifyUser";
import {
  ensureAppleHealthSource,
  toDataSourceResponse,
} from "@/server/domain/sources/ensureAppleHealthSource";
import { apiRoute, corsPreflight, json } from "@/server/http";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const source = await ensureAppleHealthSource(userId);
  return json(toDataSourceResponse(source));
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
