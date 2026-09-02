import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
  featureRequestRowSchema,
  type CreateFeatureRequest,
  type FeatureRequest,
  type RequestKind,
} from "@/lib/types/requests/feature-request";

const MAX_REQUESTS_PER_DAY = 5;
const REPORTS_TO_HIDE = 3;

function featureRequestFromRow(row: unknown): FeatureRequest {
  const parsed = featureRequestRowSchema.parse(row);
  return {
    id: parsed.id,
    kind: parsed.kind,
    status: parsed.status,
    title: parsed.title,
    body: parsed.body,
    voteCount: parsed.vote_count,
    voted: parsed.voted,
    createdAt: parsed.created_at.toISOString(),
    author: {
      userId: parsed.author_user_id,
      handle: parsed.author_handle,
      displayName: parsed.author_display_name,
    },
  };
}

export async function listFeatureRequests(
  userId: string,
  kind: RequestKind | undefined,
  database: Sql = createDatabaseClient(),
): Promise<FeatureRequest[]> {
  const rows = await database`
    select
      r.id,
      r.kind,
      r.status,
      r.title,
      r.body,
      r.created_at,
      p.user_id as author_user_id,
      p.handle as author_handle,
      p.display_name as author_display_name,
      (
        select count(*)::int
        from public.feature_request_votes v
        where v.request_id = r.id
      ) as vote_count,
      exists(
        select 1
        from public.feature_request_votes v
        where v.request_id = r.id
          and v.user_id = ${userId}
      ) as voted
    from public.feature_requests r
    join public.profiles p on p.user_id = r.author_id
    where r.hidden_at is null
      and p.deleted_at is null
      and r.author_id not in (
        select blocked_id
        from public.feature_request_blocks
        where blocker_id = ${userId}
      )
      and r.id not in (
        select request_id
        from public.feature_request_reports
        where reporter_id = ${userId}
      )
      and (${kind ?? null}::text is null or r.kind::text = ${kind ?? null})
    order by vote_count desc, r.created_at desc
    limit 100
  `;
  return rows.map((row) => featureRequestFromRow(row));
}

export async function createFeatureRequest(
  userId: string,
  input: CreateFeatureRequest,
  database: Sql = createDatabaseClient(),
): Promise<FeatureRequest> {
  return database.begin("read write", async (sql) => {
    const [recent] = await sql<{ count: number }[]>`
      select count(*)::int as count
      from public.feature_requests
      where author_id = ${userId}
        and created_at > now() - interval '24 hours'
    `;
    if ((recent?.count ?? 0) >= MAX_REQUESTS_PER_DAY) {
      throw new ApiError(
        429,
        ERROR_CODES.rate_limited,
        "You can post 5 requests per day.",
      );
    }

    const [inserted] = await sql<{ id: string }[]>`
      insert into public.feature_requests (author_id, kind, title, body)
      values (${userId}, ${input.kind}::public.request_kind, ${input.title}, ${input.body})
      returning id
    `;
    if (!inserted) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not save the request");
    }
    return loadVisibleFeatureRequest(userId, inserted.id, sql);
  });
}

export async function toggleFeatureRequestVote(
  userId: string,
  requestId: string,
  database: Sql = createDatabaseClient(),
): Promise<FeatureRequest> {
  return database.begin("read write", async (sql) => {
    await loadVisibleFeatureRequest(userId, requestId, sql);
    const [existing] = await sql<{ request_id: string }[]>`
      select request_id
      from public.feature_request_votes
      where request_id = ${requestId}
        and user_id = ${userId}
    `;
    if (existing) {
      await sql`
        delete from public.feature_request_votes
        where request_id = ${requestId}
          and user_id = ${userId}
      `;
    } else {
      await sql`
        insert into public.feature_request_votes (request_id, user_id)
        values (${requestId}, ${userId})
      `;
    }
    return loadVisibleFeatureRequest(userId, requestId, sql);
  });
}

export async function reportFeatureRequest(
  userId: string,
  requestId: string,
  database: Sql = createDatabaseClient(),
): Promise<{ reported: true; hidden: boolean }> {
  return database.begin("read write", async (sql) => {
    const request = await loadVisibleFeatureRequest(userId, requestId, sql);
    if (request.author.userId === userId) {
      throw new ApiError(400, ERROR_CODES.validation, "You cannot report your own request");
    }
    await sql`
      insert into public.feature_request_reports (request_id, reporter_id)
      values (${requestId}, ${userId})
      on conflict do nothing
    `;
    const [counts] = await sql<{ count: number }[]>`
      select count(*)::int as count
      from public.feature_request_reports
      where request_id = ${requestId}
    `;
    const hidden = (counts?.count ?? 0) >= REPORTS_TO_HIDE;
    if (hidden) {
      await sql`
        update public.feature_requests
        set hidden_at = now()
        where id = ${requestId}
          and hidden_at is null
      `;
    }
    return { reported: true as const, hidden };
  });
}

export async function blockFeatureRequestAuthor(
  userId: string,
  requestId: string,
  database: Sql = createDatabaseClient(),
): Promise<{ blocked: true }> {
  return database.begin("read write", async (sql) => {
    const request = await loadVisibleFeatureRequest(userId, requestId, sql);
    if (request.author.userId === userId) {
      throw new ApiError(400, ERROR_CODES.validation, "You cannot block yourself");
    }
    await sql`
      insert into public.feature_request_blocks (blocker_id, blocked_id)
      values (${userId}, ${request.author.userId})
      on conflict do nothing
    `;
    return { blocked: true as const };
  });
}

async function loadVisibleFeatureRequest(
  userId: string,
  requestId: string,
  sql: Sql,
): Promise<FeatureRequest> {
  const [row] = await sql`
    select
      r.id,
      r.kind,
      r.status,
      r.title,
      r.body,
      r.created_at,
      p.user_id as author_user_id,
      p.handle as author_handle,
      p.display_name as author_display_name,
      (
        select count(*)::int
        from public.feature_request_votes v
        where v.request_id = r.id
      ) as vote_count,
      exists(
        select 1
        from public.feature_request_votes v
        where v.request_id = r.id
          and v.user_id = ${userId}
      ) as voted
    from public.feature_requests r
    join public.profiles p on p.user_id = r.author_id
    where r.id = ${requestId}
      and r.hidden_at is null
      and p.deleted_at is null
      and r.author_id not in (
        select blocked_id
        from public.feature_request_blocks
        where blocker_id = ${userId}
      )
      and r.id not in (
        select request_id
        from public.feature_request_reports
        where reporter_id = ${userId}
      )
  `;
  if (!row) {
    throw new ApiError(404, ERROR_CODES.not_found, "Request not found");
  }
  return featureRequestFromRow(row);
}
