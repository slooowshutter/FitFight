import { apiRoute, corsPreflight, json } from "@/lib/http";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async () => json({ ok: true }));

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
