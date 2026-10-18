import { apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { readWhoopConnection } from "@/lib/supabase/queries/whoop-supabase-query";
import type { WhoopConnectionResponse } from "@/lib/types/whoop/whoop";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const connection = await readWhoopConnection(userId);
    const response: WhoopConnectionResponse = {
        connected: Boolean(connection?.tokens_ciphertext),
        last_synced_at: connection?.last_synced_at?.toISOString() ?? null,
        history_synced_at: connection?.history_synced_at?.toISOString() ?? null,
    };
    return json(response);
});

export const OPTIONS = corsPreflight;
