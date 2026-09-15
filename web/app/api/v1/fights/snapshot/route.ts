import { apiRoute, corsPreflight, json, readJson, measureRequestStage } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { readFightSnapshot } from "@/lib/supabase/queries/fight-snapshot-supabase-query";
import { fightSnapshotRequestSchema } from "@/lib/types/fights/fight-snapshot";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request, { timing }) => {
  const { userId } = await measureRequestStage(timing, "auth", () => verifyUser(request));
  const { time_zone: timeZone } = fightSnapshotRequestSchema.parse(await readJson(request));
  return json(await measureRequestStage(timing, "db", () => readFightSnapshot(userId, timeZone)));
}, "fights_snapshot");

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
