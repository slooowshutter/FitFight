import { verifyUser } from "@/server/auth/verifyUser";
import {
  healthKitBatchSchema,
  upsertHealthKitObservations,
} from "@/server/ingest/healthkit/upsertObservations";
import { apiRoute, corsPreflight, json, readJson } from "@/server/http";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const body = healthKitBatchSchema.parse(await readJson(request));
  const ack = await upsertHealthKitObservations(userId, body);
  return json(ack);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
