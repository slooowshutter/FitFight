import { verifyUser } from "@/server/auth/verifyUser";
import { archiveHealthKitSteps } from "@/server/ingest/healthkit/archiveSteps";
import { healthKitArchiveSchema } from "@/server/ingest/healthkit/healthKitArchiveBatch";
import { apiRoute, corsPreflight, json, readJson } from "@/server/http";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const body = healthKitArchiveSchema.parse(await readJson(request, 4_000_000));
  const ack = await archiveHealthKitSteps(userId, body);
  return json(ack);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
