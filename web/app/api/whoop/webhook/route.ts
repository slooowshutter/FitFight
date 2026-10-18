import { after, NextResponse } from "next/server";
import { apiRoute } from "@/lib/http";
import {
    findWhoopUser,
    saveWhoopRecords,
} from "@/lib/supabase/queries/whoop-supabase-query";
import { whoopRecordSchema, whoopWebhookSchema } from "@/lib/types/whoop/whoop";
import { syncWhoopUser, verifyWhoopSignature } from "@/lib/whoop/whoop";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 120;

/**
 * WHOOP pings staging and production for every member. Each answers only for people it knows, and a
 * ping carries no health data: an update fetches the person's recent records with their own token.
 */
export const POST = apiRoute(async (request) => {
    const body = await request.text();
    verifyWhoopSignature(body, request.headers);
    const payload = whoopRecordSchema.parse(JSON.parse(body));
    const event = whoopWebhookSchema.parse(payload);
    const userId = await findWhoopUser(event.user_id);
    if (userId && event.type.endsWith(".deleted")) {
        await saveWhoopRecords(
            userId,
            [
                {
                    record_kind: "deletion",
                    record_type: `whoop_${event.type.split(".")[0]}`,
                    record_key: String(event.id),
                    starts_at: null,
                    ends_at: null,
                    time_zone: null,
                    payload,
                },
            ],
            null,
        );
    } else if (userId) {
        after(() => syncWhoopUser(userId));
    }
    return new NextResponse(null, { status: 204 });
});
