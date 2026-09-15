import { after } from "next/server";
import {
    apiRoute,
    corsPreflight,
    json,
    readJson,
    requireUuid,
} from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import {
    listFightPostReactionPeople,
    setFightPostReaction,
} from "@/lib/supabase/queries/fight-post-engagement-supabase-query";
import { processNotificationOutbox } from "@/lib/supabase/queries/process-notification-outbox-supabase-query";
import {
    listFightPostReactionPeopleQuerySchema,
    setFightPostReactionRequestSchema,
} from "@/lib/types/feed/fight-post";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute<{ postID: string }>(async (request, { params }) => {
    const { userId } = await verifyUser(request);
    const parsed = listFightPostReactionPeopleQuerySchema.safeParse(
        Object.fromEntries(new URL(request.url).searchParams),
    );
    if (!parsed.success) {
        throw parsed.error;
    }
    return json(
        await listFightPostReactionPeople(
            userId,
            requireUuid(params.postID, "postID"),
            parsed.data,
        ),
    );
});

export const POST = apiRoute<{ postID: string }>(
    async (request, { params }) => {
        const { userId } = await verifyUser(request);
        const parsed = setFightPostReactionRequestSchema.safeParse(
            await readJson(request),
        );
        if (!parsed.success) {
            throw parsed.error;
        }
        const result = await setFightPostReaction(
            userId,
            requireUuid(params.postID, "postID"),
            parsed.data.emoji,
        );
        after(async () => {
            await processNotificationOutbox(new Date(), createDatabaseClient());
        });
        return json(result);
    },
);

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}
