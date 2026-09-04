import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { joinFight } from "@/lib/supabase/queries/join-fight-supabase-query";
import { joinFightRequestSchema } from "@/lib/types/fights/joinable-fight";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const parsed = joinFightRequestSchema.safeParse(await readJson(request));
  if (!parsed.success) {
    throw parsed.error;
  }
  const forwarded = request.headers.get("x-forwarded-for");
  const clientIp = forwarded?.split(",")[0]?.trim() || request.headers.get("x-real-ip");
  const fight = await joinFight(userId, parsed.data, clientIp);
  return json(fight);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
