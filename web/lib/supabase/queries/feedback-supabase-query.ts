import type { Sql } from "postgres";
import type { SupabaseClient } from "@supabase/supabase-js";
import { isFitFightAdmin } from "@/lib/admin/is-fitfight-admin";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { readAdminViewer } from "@/lib/supabase/queries/auth-supabase-query";
import {
    loadReadyMedia,
    mapMedia,
    signMediaUrls,
    type MediaRow,
} from "@/lib/supabase/queries/media-supabase-query";
import type {
    BlockFeedbackAuthorResponse,
    CreateFeedbackCommentRequest,
    CreateFeedbackPostRequest,
    FeedbackComment,
    FeedbackCommentResponse,
    FeedbackKind,
    FeedbackListResponse,
    FeedbackMetadata,
    FeedbackPostDetail,
    FeedbackPostResponse,
    FeedbackPostSummary,
    FeedbackVoteResponse,
    ListFeedbackQuery,
    ReportFeedbackPostRequest,
    ReportFeedbackPostResponse,
    UpdateFeedbackPostRequest,
} from "@/lib/types/feedback/feedback";
import { feedbackMetadataSchema } from "@/lib/types/feedback/feedback";
import type { MediaObject } from "@/lib/types/media/media";

const POST_LIMIT_PER_DAY = 8;
const COMMENT_LIMIT_PER_DAY = 30;

type FeedbackPostRow = {
    id: string;
    kind: FeedbackKind;
    title: string;
    body: string;
    vote_count: number;
    comment_count: number;
    voted: boolean;
    author_id: string;
    author_handle: string;
    mine: boolean;
    created_at: Date | string;
    metadata: unknown;
};

type FeedbackCommentRow = {
    id: string;
    body: string;
    author_handle: string;
    created_at: Date | string;
    metadata: unknown;
};

function isoUtc(value: Date | string): string {
    return new Date(value).toISOString().replace(/\.\d{3}Z$/, "Z");
}

function mapMetadata(value: unknown): FeedbackMetadata {
    const parsed = feedbackMetadataSchema.safeParse(value ?? {});
    return parsed.success ? parsed.data : {};
}

function mapPost(
    row: FeedbackPostRow,
    media: MediaObject[] = [],
): FeedbackPostSummary {
    return {
        id: row.id,
        kind: row.kind,
        title: row.title,
        body: row.body,
        vote_count: row.vote_count,
        comment_count: row.comment_count,
        voted: row.voted,
        author_id: row.author_id,
        author_handle: row.author_handle,
        mine: row.mine,
        created_at: isoUtc(row.created_at),
        metadata: mapMetadata(row.metadata),
        media,
    };
}

type FeedbackMediaRow = MediaRow & { post_id: string };

async function loadFeedbackMedia(
    postIds: string[],
    database: Sql,
): Promise<Map<string, MediaObject[]>> {
    const byPost = new Map<string, MediaObject[]>();
    if (postIds.length === 0) return byPost;
    const rows = await database<FeedbackMediaRow[]>`
        select
            attachment.post_id,
            media.id, media.owner_id, media.kind::text as kind, media.purpose::text as purpose,
            media.status::text as status, media.object_path, media.original_filename,
            media.content_type, media.byte_size::text, media.width, media.height,
            media.duration_ms, media.sha256, media.created_at
        from public.feedback_post_media as attachment
        join public.media_objects as media on media.id = attachment.media_id
        where attachment.post_id in ${database(postIds)}
            and media.status = 'ready'
        order by attachment.post_id, attachment.sort, media.id
    `;
    const urls = await signMediaUrls(rows.map((row) => row.object_path));
    for (const row of rows) {
        const list = byPost.get(row.post_id) ?? [];
        list.push(mapMedia(row, urls.get(row.object_path) ?? null));
        byPost.set(row.post_id, list);
    }
    return byPost;
}

async function prepareFeedbackMedia(
    userId: string,
    mediaIds: string[],
    database: Sql,
): Promise<string[]> {
    const uniqueMediaIds = [...new Set(mediaIds)];
    if (uniqueMediaIds.length === 0) return [];
    const media = await loadReadyMedia(
        userId,
        uniqueMediaIds,
        "feedback",
        database,
    );
    if (media.length !== uniqueMediaIds.length) {
        throw new ApiError(
            400,
            ERROR_CODES.validation,
            "Every photo, video, or file must be one you just uploaded",
        );
    }
    const [fightTaken] = await database<{ n: number }[]>`
        select count(*)::int as n
        from public.fight_post_media
        where media_id in ${database(uniqueMediaIds)}
    `;
    const [feedbackTaken] = await database<{ n: number }[]>`
        select count(*)::int as n
        from public.feedback_post_media
        where media_id in ${database(uniqueMediaIds)}
    `;
    if ((fightTaken?.n ?? 0) + (feedbackTaken?.n ?? 0) > 0) {
        throw new ApiError(
            409,
            ERROR_CODES.conflict,
            "A file was already used on another post",
        );
    }
    return uniqueMediaIds;
}

function mapComment(row: FeedbackCommentRow): FeedbackComment {
    return {
        id: row.id,
        body: row.body,
        author_handle: row.author_handle,
        created_at: isoUtc(row.created_at),
        metadata: mapMetadata(row.metadata),
    };
}

function jsonMetadata(metadata: FeedbackMetadata | undefined) {
    return JSON.parse(JSON.stringify(metadata ?? {}));
}

export async function listFeedbackPosts(
    userId: string,
    query: ListFeedbackQuery,
    database: Sql = createDatabaseClient(),
): Promise<FeedbackListResponse> {
    const kind = query.kind ?? null;
    const rows = await database<FeedbackPostRow[]>`
        select
            post.id,
            post.kind::text as kind,
            post.title,
            post.body,
            (
                select count(*)::int
                from public.feedback_votes as vote
                where vote.post_id = post.id
            ) as vote_count,
            (
                select count(*)::int
                from public.feedback_comments as comment
                where comment.post_id = post.id
            ) as comment_count,
            exists(
                select 1
                from public.feedback_votes as vote
                where vote.post_id = post.id
                    and vote.user_id = ${userId}
            ) as voted,
            post.author_id,
            profile.handle as author_handle,
            post.author_id = ${userId} as mine,
            post.created_at,
            coalesce(post.metadata, '{}'::jsonb) as metadata
        from public.feedback_posts as post
        join public.profiles as profile
            on profile.user_id = post.author_id
          and profile.deleted_at is null
        where (${kind}::text is null or post.kind::text = ${kind})
            and not exists (
                select 1 from private.feedback_blocks as blocked
                where blocked.blocker_id = ${userId}
                    and blocked.blocked_id = post.author_id
            )
        order by vote_count desc, post.created_at desc
        limit 100
    `;
    const attachments = await loadFeedbackMedia(
        rows.map((row) => row.id),
        database,
    );
    return {
        posts: rows.map((row) => mapPost(row, attachments.get(row.id) ?? [])),
    };
}

export async function getFeedbackPost(
    userId: string,
    postId: string,
    database: Sql = createDatabaseClient(),
): Promise<FeedbackPostDetail> {
    const [row] = await database<FeedbackPostRow[]>`
        select
            post.id,
            post.kind::text as kind,
            post.title,
            post.body,
            (
                select count(*)::int
                from public.feedback_votes as vote
                where vote.post_id = post.id
            ) as vote_count,
            (
                select count(*)::int
                from public.feedback_comments as comment
                where comment.post_id = post.id
            ) as comment_count,
            exists(
                select 1
                from public.feedback_votes as vote
                where vote.post_id = post.id
                    and vote.user_id = ${userId}
            ) as voted,
            post.author_id,
            profile.handle as author_handle,
            post.author_id = ${userId} as mine,
            post.created_at,
            coalesce(post.metadata, '{}'::jsonb) as metadata
        from public.feedback_posts as post
        join public.profiles as profile
            on profile.user_id = post.author_id
          and profile.deleted_at is null
        where post.id = ${postId}
            and not exists (
                select 1 from private.feedback_blocks as blocked
                where blocked.blocker_id = ${userId}
                    and blocked.blocked_id = post.author_id
            )
    `;
    if (!row) {
        throw new ApiError(404, ERROR_CODES.not_found, "Request not found");
    }
    const comments = await database<FeedbackCommentRow[]>`
        select
            comment.id,
            comment.body,
            profile.handle as author_handle,
            comment.created_at,
            coalesce(comment.metadata, '{}'::jsonb) as metadata
        from public.feedback_comments as comment
        join public.profiles as profile
            on profile.user_id = comment.author_id
          and profile.deleted_at is null
        where comment.post_id = ${postId}
            and not exists (
                select 1 from private.feedback_blocks as blocked
                where blocked.blocker_id = ${userId}
                    and blocked.blocked_id = comment.author_id
            )
        order by comment.created_at
    `;
    const attachments = await loadFeedbackMedia([row.id], database);
    return {
        post: mapPost(row, attachments.get(row.id) ?? []),
        comments: comments.map(mapComment),
    };
}

/** The author or an admin removes the post; foreign keys remove its comments, votes, reports, and attachment links. */
export async function deleteFeedbackPost(
    userId: string,
    postId: string,
    admin: SupabaseClient = createAdminClient(),
    database: Sql = createDatabaseClient(),
): Promise<void> {
    const [post] = await database<{ id: string; author_id: string }[]>`
        select id, author_id
        from public.feedback_posts
        where id = ${postId}
    `;
    if (!post) {
        throw new ApiError(404, ERROR_CODES.not_found, "Request not found");
    }
    if (post.author_id !== userId) {
        const viewer = await readAdminViewer(userId, admin);
        if (!isFitFightAdmin(viewer)) {
            throw new ApiError(
                403,
                ERROR_CODES.forbidden,
                "You can only delete your own request.",
            );
        }
    }
    const deleted = await database`
        delete from public.feedback_posts
        where id = ${postId}
        returning id
    `;
    if (deleted.length === 0) {
        throw new ApiError(404, ERROR_CODES.not_found, "Request not found");
    }
}

export async function updateFeedbackPost(
    userId: string,
    postId: string,
    input: UpdateFeedbackPostRequest,
    database: Sql = createDatabaseClient(),
): Promise<FeedbackPostResponse> {
    const [post] = await database<{ id: string; author_id: string }[]>`
        select id, author_id
        from public.feedback_posts
        where id = ${postId}
    `;
    if (!post) {
        throw new ApiError(404, ERROR_CODES.not_found, "Request not found");
    }
    if (post.author_id !== userId) {
        throw new ApiError(
            403,
            ERROR_CODES.forbidden,
            "You can only edit your own request.",
        );
    }
    const [row] = await database<FeedbackPostRow[]>`
        update public.feedback_posts
        set
            kind = ${input.kind}::public.feedback_kind,
            title = ${input.title},
            body = ${input.body}
        where id = ${postId}
            and author_id = ${userId}
        returning
            id,
            kind::text as kind,
            title,
            body,
            (
                select count(*)::int
                from public.feedback_votes as vote
                where vote.post_id = public.feedback_posts.id
            ) as vote_count,
            (
                select count(*)::int
                from public.feedback_comments as comment
                where comment.post_id = public.feedback_posts.id
            ) as comment_count,
            exists(
                select 1
                from public.feedback_votes as vote
                where vote.post_id = public.feedback_posts.id
                    and vote.user_id = ${userId}
            ) as voted,
            author_id,
            (
                select handle
                from public.profiles
                where user_id = ${userId}
                    and deleted_at is null
            ) as author_handle,
            true as mine,
            created_at,
            metadata
    `;
    if (!row) {
        throw new ApiError(404, ERROR_CODES.not_found, "Request not found");
    }
    if (!row.author_handle) {
        throw new ApiError(
            400,
            ERROR_CODES.profile_missing,
            "Profile is missing",
        );
    }
    const attachments = await loadFeedbackMedia([row.id], database);
    return { post: mapPost(row, attachments.get(row.id) ?? []) };
}

export async function createFeedbackPost(
    userId: string,
    input: CreateFeedbackPostRequest,
    database: Sql = createDatabaseClient(),
): Promise<FeedbackPostResponse> {
    const [rate] = await database<{ n: number }[]>`
        select count(*)::int as n
        from public.feedback_posts
        where author_id = ${userId}
            and created_at > now() - interval '24 hours'
    `;
    if ((rate?.n ?? 0) >= POST_LIMIT_PER_DAY) {
        throw new ApiError(
            429,
            ERROR_CODES.rate_limited,
            "You’ve posted a few times recently. Try again later.",
        );
    }

    if (input.media_ids.length === 0) {
        const [row] = await insertFeedbackPost(userId, input, database);
        if (!row?.author_handle) {
            throw new ApiError(
                400,
                ERROR_CODES.profile_missing,
                "Profile is missing",
            );
        }
        return { post: mapPost(row, []) };
    }

    const created = await database.begin("read write", async (sql) => {
        const mediaIds = await prepareFeedbackMedia(
            userId,
            input.media_ids,
            sql,
        );
        const [row] = await insertFeedbackPost(userId, input, sql);
        if (!row?.author_handle) {
            throw new ApiError(
                400,
                ERROR_CODES.profile_missing,
                "Profile is missing",
            );
        }
        for (const [index, mediaId] of mediaIds.entries()) {
            await sql`
                insert into public.feedback_post_media (post_id, media_id, sort)
                values (${row.id}, ${mediaId}, ${index})
            `;
        }
        return row;
    });
    const attachments = await loadFeedbackMedia([created.id], database);
    return { post: mapPost(created, attachments.get(created.id) ?? []) };
}

async function insertFeedbackPost(
    userId: string,
    input: CreateFeedbackPostRequest,
    database: Sql,
): Promise<FeedbackPostRow[]> {
    // NOTE: sql.json(object) so postgres.js sends jsonb. JSON.stringify(text)::jsonb is stringified again and fails feedback_posts_metadata_object.
    return database<FeedbackPostRow[]>`
        insert into public.feedback_posts (author_id, kind, title, body, metadata)
        values (
            ${userId},
            ${input.kind}::public.feedback_kind,
            ${input.title},
            ${input.body},
            ${database.json(jsonMetadata(input.metadata))}::jsonb
        )
        returning
            id,
            kind::text as kind,
            title,
            body,
            0 as vote_count,
            0 as comment_count,
            false as voted,
            ${userId} as author_id,
            (
                select handle
                from public.profiles
                where user_id = ${userId}
                    and deleted_at is null
            ) as author_handle,
            true as mine,
            created_at,
            metadata
    `;
}

export async function toggleFeedbackVote(
    userId: string,
    postId: string,
    database: Sql = createDatabaseClient(),
): Promise<FeedbackVoteResponse> {
    return database.begin("read write", async (sql) => {
        const [post] = await sql<{ id: string }[]>`
            select id from public.feedback_posts where id = ${postId}
        `;
        if (!post) {
            throw new ApiError(404, ERROR_CODES.not_found, "Request not found");
        }

        const deleted = await sql<{ post_id: string }[]>`
            delete from public.feedback_votes
            where post_id = ${postId} and user_id = ${userId}
            returning post_id
        `;
        let voted = false;
        if (deleted.length === 0) {
            await sql`
                insert into public.feedback_votes (post_id, user_id)
                values (${postId}, ${userId})
                on conflict (post_id, user_id) do nothing
            `;
            voted = true;
        }
        const [counts] = await sql<{ vote_count: number }[]>`
            select count(*)::int as vote_count
            from public.feedback_votes
            where post_id = ${postId}
        `;
        return { voted, vote_count: counts?.vote_count ?? 0 };
    });
}

export async function createFeedbackComment(
    userId: string,
    postId: string,
    input: CreateFeedbackCommentRequest,
    database: Sql = createDatabaseClient(),
): Promise<FeedbackCommentResponse> {
    const [rate] = await database<{ n: number }[]>`
        select count(*)::int as n
        from public.feedback_comments
        where author_id = ${userId}
            and created_at > now() - interval '24 hours'
    `;
    if ((rate?.n ?? 0) >= COMMENT_LIMIT_PER_DAY) {
        throw new ApiError(
            429,
            ERROR_CODES.rate_limited,
            "You’ve commented a few times recently. Try again later.",
        );
    }

    const [comment] = await database<FeedbackCommentRow[]>`
        insert into public.feedback_comments (post_id, author_id, body, metadata)
        select ${postId}, ${userId}, ${input.body}, ${database.json(jsonMetadata(input.metadata))}::jsonb
        where exists (
            select 1 from public.feedback_posts where id = ${postId}
        )
        returning
            id,
            body,
            (
                select handle
                from public.profiles
                where user_id = ${userId}
                    and deleted_at is null
            ) as author_handle,
            created_at,
            metadata
    `;
    if (!comment) {
        throw new ApiError(404, ERROR_CODES.not_found, "Request not found");
    }
    if (!comment.author_handle) {
        throw new ApiError(
            400,
            ERROR_CODES.profile_missing,
            "Profile is missing",
        );
    }
    return { comment: mapComment(comment) };
}

export async function reportFeedbackPost(
    userId: string,
    postId: string,
    input: ReportFeedbackPostRequest,
    database: Sql = createDatabaseClient(),
): Promise<ReportFeedbackPostResponse> {
    const [post] = await database<{ id: string; author_id: string }[]>`
        select post.id, post.author_id
        from public.feedback_posts as post
        join public.profiles as profile
            on profile.user_id = post.author_id
          and profile.deleted_at is null
        where post.id = ${postId}
            and not exists (
                select 1 from private.feedback_blocks as blocked
                where blocked.blocker_id = ${userId}
                    and blocked.blocked_id = post.author_id
            )
    `;
    if (!post) {
        throw new ApiError(404, ERROR_CODES.not_found, "Request not found");
    }
    if (post.author_id === userId) {
        throw new ApiError(
            400,
            ERROR_CODES.validation,
            "You cannot report your own post",
        );
    }
    await database`
        insert into private.feedback_post_reports (post_id, reporter_id, reason)
        values (${postId}, ${userId}, ${input.reason})
        on conflict (post_id, reporter_id) do update set reason = excluded.reason
    `;
    return { reported: true };
}

export async function blockFeedbackAuthor(
    userId: string,
    blockedId: string,
    database: Sql = createDatabaseClient(),
): Promise<BlockFeedbackAuthorResponse> {
    if (userId === blockedId) {
        throw new ApiError(
            400,
            ERROR_CODES.validation,
            "You cannot hide yourself",
        );
    }
    const [profile] = await database<{ user_id: string }[]>`
        select user_id from public.profiles
        where user_id = ${blockedId} and deleted_at is null
    `;
    if (!profile) {
        throw new ApiError(
            404,
            ERROR_CODES.not_found,
            "That person is not on FitFight",
        );
    }
    await database`
        insert into private.feedback_blocks (blocker_id, blocked_id)
        values (${userId}, ${blockedId})
        on conflict (blocker_id, blocked_id) do nothing
    `;
    return { blocked: true };
}
