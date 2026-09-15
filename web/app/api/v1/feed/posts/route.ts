import { after } from "next/server";
import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { processNotificationOutbox } from "@/lib/supabase/queries/process-notification-outbox-supabase-query";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { createFeedPosts } from "@/lib/supabase/queries/fight-posts-supabase-query";
import { createFeedPostsRequestSchema } from "@/lib/types/feed/fight-post";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const parsed = createFeedPostsRequestSchema.safeParse(await readJson(request));
  if (!parsed.success) {
    throw parsed.error;
  }
  const result = await createFeedPosts(userId, parsed.data);
  after(async () => { await processNotificationOutbox(new Date(), createDatabaseClient()); });
  return json(result, 201);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}
