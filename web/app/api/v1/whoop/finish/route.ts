import { after } from "next/server";
import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { whoopFinishRequestSchema } from "@/lib/types/whoop/whoop";
import { finishWhoopConnection, syncWhoopUser } from "@/lib/whoop/whoop";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
// The first sync pulls the person's whole WHOOP history after the response.
export const maxDuration = 300;

export const POST = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const input = whoopFinishRequestSchema.parse(await readJson(request, 4096));
    await finishWhoopConnection(userId, input.code, input.state);
    after(() => syncWhoopUser(userId));
    return json({ connected: true });
});

export const OPTIONS = corsPreflight;
