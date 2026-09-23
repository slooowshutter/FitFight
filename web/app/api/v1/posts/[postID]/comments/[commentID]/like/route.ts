import { apiRoute, corsPreflight, json, readJson, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { setFightPostCommentLike } from "@/lib/supabase/queries/fight-post-engagement-supabase-query";
import { setFightPostCommentLikeRequestSchema } from "@/lib/types/feed/fight-post";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const PUT = apiRoute<{ postID: string; commentID: string }>(
    async (request, { params }) => {
        const { userId } = await verifyUser(request);
        const parsed = setFightPostCommentLikeRequestSchema.safeParse(await readJson(request));
        if (!parsed.success) {
            throw parsed.error;
        }
        return json(await setFightPostCommentLike(
            userId,
            requireUuid(params.postID, "postID"),
            requireUuid(params.commentID, "commentID"),
            parsed.data.liked,
        ));
    },
);

export const OPTIONS = corsPreflight;
