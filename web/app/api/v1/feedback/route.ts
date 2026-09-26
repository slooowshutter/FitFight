import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { createAppFeedbackBacklogItem } from "@/lib/notion/create-app-feedback-item";
import { readAdminViewer, verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { isFitFightAdmin } from "@/lib/admin/is-fitfight-admin";
import {
    createFeedbackPost,
    listFeedbackPosts,
} from "@/lib/supabase/queries/feedback-supabase-query";
import {
    createFeedbackPostRequestSchema,
    listFeedbackQuerySchema,
} from "@/lib/types/feedback/feedback";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const params = new URL(request.url).searchParams;
    const parsed = listFeedbackQuerySchema.safeParse({
        kind: params.get("kind") || undefined,
        status: params.get("status") ?? undefined,
        sort: params.get("sort") ?? undefined,
    });
    if (!parsed.success) {
        throw parsed.error;
    }
    const listed = await listFeedbackPosts(userId, parsed.data);
    return json({
        posts: listed.posts.map((post) => ({ ...post, metadata: {} })),
        can_archive: isFitFightAdmin(await readAdminViewer(userId)),
    });
});

export const POST = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const parsed = createFeedbackPostRequestSchema.safeParse(
        await readJson(request),
    );
    if (!parsed.success) {
        throw parsed.error;
    }
    const created = await createFeedbackPost(userId, parsed.data);
    await createAppFeedbackBacklogItem(created.post);
    return json({ post: { ...created.post, metadata: {} } }, 201);
});

export const OPTIONS = corsPreflight;
