import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { companionIdSchema } from "@/lib/types/companions/companion";
import {
    fightPostCommentResponseSchema,
    fightPostReactionPersonSchema,
    type DeleteFightPostCommentResponse,
} from "@/lib/types/feed/fight-post";
import type {
    CreateFightPostCommentRequest,
    FightPostAuthor,
    FightPostComment,
    FightPostCommentListResponse,
    FightPostCommentResponse,
    FightPostReactionResponse,
    FightPostReactionPeopleResponse,
    ListFightPostCommentsQuery,
    ListFightPostReactionPeopleQuery,
    ReportFightPostCommentRequest,
    ReportFightPostCommentResponse,
} from "@/lib/types/feed/fight-post";
import {
    loadVisiblePost,
    listPostReactions,
} from "./fight-posts-supabase-query";
import { mapMedia, signMediaUrls, type MediaRow } from "./media-supabase-query";
import {
    eligibleMentionUserIds,
    enqueueFightFeedCommentNotifications,
    enqueueFightFeedReactionNotifications,
    enqueueMentionNotifications,
    mentionHandlesFromBody,
} from "./feed-social-notifications-supabase-query";

const COMMENT_LIMIT_PER_DAY = 40;

type CommentRow = {
    id: string;
    post_id: string;
    parent_id: string | null;
    body: string;
    created_at: Date | string;
    author_id: string;
    author_handle: string;
    author_display_name: string;
    author_companion_id: string | null;
    avatar_id: string | null;
    avatar_kind: MediaRow["kind"] | null;
    avatar_purpose: MediaRow["purpose"] | null;
    avatar_status: MediaRow["status"] | null;
    avatar_object_path: string | null;
    avatar_original_filename: string | null;
    avatar_content_type: MediaRow["content_type"] | null;
    avatar_byte_size: string | number | null;
    avatar_width: number | null;
    avatar_height: number | null;
    avatar_duration_ms: number | null;
    avatar_sha256: string | null;
    avatar_created_at: Date | string | null;
};

function isoUtc(value: Date | string): string {
    return new Date(value).toISOString().replace(/\.\d{3}Z$/, "Z");
}

function cursorStamp(value: Date | string): string {
    return value instanceof Date ? value.toISOString() : value;
}

function parseCursor(
    cursor: string | undefined,
): { createdAt: string; id: string } | null {
    if (!cursor) return null;
    const separator = cursor.lastIndexOf("|");
    if (separator <= 0) {
        throw new ApiError(400, ERROR_CODES.validation, "cursor is invalid");
    }
    const createdAt = cursor.slice(0, separator);
    const id = cursor.slice(separator + 1);
    if (
        !Number.isFinite(Date.parse(createdAt)) ||
        !/^[0-9a-f-]{36}$/i.test(id)
    ) {
        throw new ApiError(400, ERROR_CODES.validation, "cursor is invalid");
    }
    return { createdAt, id };
}

function parseDiscussedCursor(
    cursor: string | undefined,
): { replyCount: number; createdAt: string; id: string } | null {
    if (!cursor) return null;
    const parts = cursor.split("|");
    if (parts.length !== 3) {
        throw new ApiError(400, ERROR_CODES.validation, "cursor is invalid");
    }
    const replyCount = Number(parts[0]);
    const createdAt = parts[1];
    const id = parts[2];
    if (
        createdAt === undefined ||
        id === undefined ||
        !Number.isInteger(replyCount) ||
        replyCount < 0 ||
        !Number.isFinite(Date.parse(createdAt)) ||
        !/^[0-9a-f-]{36}$/i.test(id)
    ) {
        throw new ApiError(400, ERROR_CODES.validation, "cursor is invalid");
    }
    return { replyCount, createdAt, id };
}

function authorFromRow(row: CommentRow, url: string | null): FightPostAuthor {
    if (
        !row.avatar_id ||
        !row.avatar_kind ||
        !row.avatar_purpose ||
        !row.avatar_status ||
        !row.avatar_object_path ||
        !row.avatar_original_filename ||
        !row.avatar_content_type ||
        row.avatar_byte_size === null ||
        row.avatar_width === null ||
        row.avatar_height === null ||
        !row.avatar_sha256 ||
        !row.avatar_created_at
    ) {
        return {
            user_id: row.author_id,
            handle: row.author_handle,
            display_name: row.author_display_name,
            avatar: null,
            companion_id: companionIdSchema
                .nullable()
                .parse(row.author_companion_id),
        };
    }
    return {
        user_id: row.author_id,
        handle: row.author_handle,
        display_name: row.author_display_name,
        avatar: mapMedia(
            {
                id: row.avatar_id,
                owner_id: row.author_id,
                kind: row.avatar_kind,
                purpose: row.avatar_purpose,
                status: row.avatar_status,
                object_path: row.avatar_object_path,
                original_filename: row.avatar_original_filename,
                content_type: row.avatar_content_type,
                byte_size: row.avatar_byte_size,
                width: row.avatar_width,
                height: row.avatar_height,
                duration_ms: row.avatar_duration_ms,
                sha256: row.avatar_sha256,
                created_at: row.avatar_created_at,
            },
            url,
        ),
        companion_id: companionIdSchema
            .nullable()
            .parse(row.author_companion_id),
    };
}

async function mapComments(
    userId: string,
    rows: CommentRow[],
): Promise<FightPostComment[]> {
    const urls = await signMediaUrls(
        rows.flatMap((row) =>
            row.avatar_object_path ? [row.avatar_object_path] : [],
        ),
    );
    return rows.map((row) => ({
        id: row.id,
        post_id: row.post_id,
        parent_id: row.parent_id,
        body: row.body,
        created_at: isoUtc(row.created_at),
        mine: row.author_id === userId,
        author: authorFromRow(
            row,
            row.avatar_object_path
                ? (urls.get(row.avatar_object_path) ?? null)
                : null,
        ),
    }));
}

async function readVisibleCommentCount(
    userId: string,
    postId: string,
    database: Sql,
): Promise<number> {
    const [row] = await database`
        select count(*)::int as comment_count
        from public.fight_post_comments as comment
        where comment.post_id = ${postId}
            and not exists (
                select 1 from private.feed_blocks as blocked
                where blocked.blocker_id = ${userId} and blocked.blocked_id = comment.author_id
            )
    `;
    return fightPostCommentResponseSchema.shape.comment_count.parse(
        row.comment_count,
    );
}

export async function listFightPostComments(
    userId: string,
    postId: string,
    query: ListFightPostCommentsQuery,
    database: Sql = createDatabaseClient(),
): Promise<FightPostCommentListResponse> {
    await loadVisiblePost(userId, postId, database);
    switch (query.sort) {
        case "recent":
            return listRecentFightPostComments(
                userId,
                postId,
                query,
                database,
            );
        case "comments":
            return listDiscussedFightPostComments(
                userId,
                postId,
                query,
                database,
            );
        case undefined:
            break;
        default: {
            const _never: never = query.sort;
            throw _never;
        }
    }
    const cursor = parseCursor(query.cursor);
    const rows = cursor
        ? await database<CommentRow[]>`
                select
                    comment.id, comment.post_id, comment.parent_id, comment.body,
                    to_char(comment.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as created_at,
                    comment.author_id, profile.handle as author_handle, profile.display_name as author_display_name,
                    profile.companion_id as author_companion_id,
                    avatar.id as avatar_id, avatar.kind::text as avatar_kind, avatar.purpose::text as avatar_purpose,
                    avatar.status::text as avatar_status, avatar.object_path as avatar_object_path,
                    avatar.original_filename as avatar_original_filename, avatar.content_type as avatar_content_type,
                    avatar.byte_size::text as avatar_byte_size, avatar.width as avatar_width,
                    avatar.height as avatar_height, avatar.duration_ms as avatar_duration_ms,
                    avatar.sha256 as avatar_sha256, avatar.created_at as avatar_created_at
                from public.fight_post_comments as comment
                join public.profiles as profile
                    on profile.id = comment.author_id and profile.deleted_at is null
                left join public.media_objects as avatar
                    on avatar.id = profile.avatar_media_id and avatar.status = 'ready'
                where comment.post_id = ${postId}
                    and not exists (
                        select 1 from private.feed_blocks as blocked
                        where blocked.blocker_id = ${userId} and blocked.blocked_id = comment.author_id
                    )
                    and (comment.created_at, comment.id) > (coalesce(
                        (select anchor.created_at from public.fight_post_comments anchor where anchor.id = ${cursor.id}::uuid and anchor.post_id = ${postId}),
                        ${cursor.createdAt}::text::timestamptz
                    ), ${cursor.id}::uuid)
                order by comment.created_at, comment.id
                limit ${query.limit + 1}
            `
        : await database<CommentRow[]>`
                select
                    comment.id, comment.post_id, comment.parent_id, comment.body,
                    to_char(comment.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as created_at,
                    comment.author_id, profile.handle as author_handle, profile.display_name as author_display_name,
                    profile.companion_id as author_companion_id,
                    avatar.id as avatar_id, avatar.kind::text as avatar_kind, avatar.purpose::text as avatar_purpose,
                    avatar.status::text as avatar_status, avatar.object_path as avatar_object_path,
                    avatar.original_filename as avatar_original_filename, avatar.content_type as avatar_content_type,
                    avatar.byte_size::text as avatar_byte_size, avatar.width as avatar_width,
                    avatar.height as avatar_height, avatar.duration_ms as avatar_duration_ms,
                    avatar.sha256 as avatar_sha256, avatar.created_at as avatar_created_at
                from public.fight_post_comments as comment
                join public.profiles as profile
                    on profile.id = comment.author_id and profile.deleted_at is null
                left join public.media_objects as avatar
                    on avatar.id = profile.avatar_media_id and avatar.status = 'ready'
                where comment.post_id = ${postId}
                    and not exists (
                        select 1 from private.feed_blocks as blocked
                        where blocked.blocker_id = ${userId} and blocked.blocked_id = comment.author_id
                    )
                order by comment.created_at, comment.id
                limit ${query.limit + 1}
            `;
    const page = rows.slice(0, query.limit);
    const last = page.at(-1);
    return {
        comments: await mapComments(userId, page),
        next_cursor:
            rows.length > query.limit && last
                ? `${cursorStamp(last.created_at)}|${last.id}`
                : null,
    };
}

async function listRecentFightPostComments(
    userId: string,
    postId: string,
    query: ListFightPostCommentsQuery,
    database: Sql,
): Promise<FightPostCommentListResponse> {
    const cursor = parseCursor(query.cursor);
    const rows = cursor
        ? await database<CommentRow[]>`
                select
                    comment.id, comment.post_id, comment.parent_id, comment.body,
                    to_char(comment.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as created_at,
                    comment.author_id, profile.handle as author_handle, profile.display_name as author_display_name,
                    profile.companion_id as author_companion_id,
                    avatar.id as avatar_id, avatar.kind::text as avatar_kind, avatar.purpose::text as avatar_purpose,
                    avatar.status::text as avatar_status, avatar.object_path as avatar_object_path,
                    avatar.original_filename as avatar_original_filename, avatar.content_type as avatar_content_type,
                    avatar.byte_size::text as avatar_byte_size, avatar.width as avatar_width,
                    avatar.height as avatar_height, avatar.duration_ms as avatar_duration_ms,
                    avatar.sha256 as avatar_sha256, avatar.created_at as avatar_created_at
                from public.fight_post_comments as comment
                join public.profiles as profile
                    on profile.id = comment.author_id and profile.deleted_at is null
                left join public.media_objects as avatar
                    on avatar.id = profile.avatar_media_id and avatar.status = 'ready'
                where comment.post_id = ${postId}
                    and not exists (
                        select 1 from private.feed_blocks as blocked
                        where blocked.blocker_id = ${userId} and blocked.blocked_id = comment.author_id
                    )
                    and (comment.created_at, comment.id) < (coalesce(
                        (select anchor.created_at from public.fight_post_comments anchor where anchor.id = ${cursor.id}::uuid and anchor.post_id = ${postId}),
                        ${cursor.createdAt}::text::timestamptz
                    ), ${cursor.id}::uuid)
                order by comment.created_at desc, comment.id desc
                limit ${query.limit + 1}
            `
        : await database<CommentRow[]>`
                select
                    comment.id, comment.post_id, comment.parent_id, comment.body,
                    to_char(comment.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as created_at,
                    comment.author_id, profile.handle as author_handle, profile.display_name as author_display_name,
                    profile.companion_id as author_companion_id,
                    avatar.id as avatar_id, avatar.kind::text as avatar_kind, avatar.purpose::text as avatar_purpose,
                    avatar.status::text as avatar_status, avatar.object_path as avatar_object_path,
                    avatar.original_filename as avatar_original_filename, avatar.content_type as avatar_content_type,
                    avatar.byte_size::text as avatar_byte_size, avatar.width as avatar_width,
                    avatar.height as avatar_height, avatar.duration_ms as avatar_duration_ms,
                    avatar.sha256 as avatar_sha256, avatar.created_at as avatar_created_at
                from public.fight_post_comments as comment
                join public.profiles as profile
                    on profile.id = comment.author_id and profile.deleted_at is null
                left join public.media_objects as avatar
                    on avatar.id = profile.avatar_media_id and avatar.status = 'ready'
                where comment.post_id = ${postId}
                    and not exists (
                        select 1 from private.feed_blocks as blocked
                        where blocked.blocker_id = ${userId} and blocked.blocked_id = comment.author_id
                    )
                order by comment.created_at desc, comment.id desc
                limit ${query.limit + 1}
            `;
    const page = rows.slice(0, query.limit);
    const last = page.at(-1);
    return {
        comments: await mapComments(userId, page),
        next_cursor:
            rows.length > query.limit && last
                ? `${cursorStamp(last.created_at)}|${last.id}`
                : null,
    };
}

async function listDiscussedFightPostComments(
    userId: string,
    postId: string,
    query: ListFightPostCommentsQuery,
    database: Sql,
): Promise<FightPostCommentListResponse> {
    const cursor = parseDiscussedCursor(query.cursor);
    const rows = await database<CommentRow[]>`
        select
            comment.id, comment.post_id, comment.parent_id, comment.body, comment.created_at,
            comment.author_id, profile.handle as author_handle, profile.display_name as author_display_name,
            profile.companion_id as author_companion_id,
            avatar.id as avatar_id, avatar.kind::text as avatar_kind, avatar.purpose::text as avatar_purpose,
            avatar.status::text as avatar_status, avatar.object_path as avatar_object_path,
            avatar.original_filename as avatar_original_filename, avatar.content_type as avatar_content_type,
            avatar.byte_size::text as avatar_byte_size, avatar.width as avatar_width,
            avatar.height as avatar_height, avatar.duration_ms as avatar_duration_ms,
            avatar.sha256 as avatar_sha256, avatar.created_at as avatar_created_at
        from public.fight_post_comments as comment
        join public.profiles as profile
            on profile.id = comment.author_id and profile.deleted_at is null
        left join public.media_objects as avatar
            on avatar.id = profile.avatar_media_id and avatar.status = 'ready'
        where comment.post_id = ${postId}
            and not exists (
                select 1 from private.feed_blocks as blocked
                where blocked.blocker_id = ${userId} and blocked.blocked_id = comment.author_id
            )
        order by comment.created_at, comment.id
    `;
    const ids = new Set(rows.map((row) => row.id));
    const children = new Map<string, CommentRow[]>();
    for (const row of rows) {
        if (!row.parent_id || !ids.has(row.parent_id)) continue;
        const siblings = children.get(row.parent_id) ?? [];
        siblings.push(row);
        children.set(row.parent_id, siblings);
    }
    const replyCountById = new Map<string, number>();
    const replyCount = (row: CommentRow): number => {
        const cached = replyCountById.get(row.id);
        if (cached !== undefined) return cached;
        let count = 0;
        const pending = [...(children.get(row.id) ?? [])];
        while (pending.length > 0) {
            const next = pending.pop();
            if (!next) continue;
            count += 1;
            pending.push(...(children.get(next.id) ?? []));
        }
        replyCountById.set(row.id, count);
        return count;
    };
    const roots = rows.filter(
        (row) => row.parent_id === null || !ids.has(row.parent_id),
    );
    roots.sort((left, right) => {
        const leftCount = replyCount(left);
        const rightCount = replyCount(right);
        if (leftCount !== rightCount) return rightCount - leftCount;
        const leftTime = cursorStamp(left.created_at);
        const rightTime = cursorStamp(right.created_at);
        if (leftTime !== rightTime) return leftTime < rightTime ? 1 : -1;
        return right.id.localeCompare(left.id);
    });
    let offset = 0;
    if (cursor) {
        offset = roots.findIndex((row) => {
            const count = replyCount(row);
            if (count !== cursor.replyCount) return count < cursor.replyCount;
            const created = new Date(row.created_at).toISOString();
            if (created !== cursor.createdAt) return created < cursor.createdAt;
            return row.id < cursor.id;
        });
        if (offset < 0) offset = roots.length;
    }
    const pageRoots = roots.slice(offset, offset + query.limit);
    const page: CommentRow[] = [];
    const take = (row: CommentRow) => {
        page.push(row);
        for (const child of children.get(row.id) ?? []) {
            take(child);
        }
    };
    for (const root of pageRoots) {
        take(root);
    }
    const last = pageRoots.at(-1);
    return {
        comments: await mapComments(userId, page),
        next_cursor:
            offset + query.limit < roots.length && last
                ? `${replyCount(last)}|${new Date(last.created_at).toISOString()}|${last.id}`
                : null,
    };
}

export async function createFightPostComment(
    userId: string,
    postId: string,
    input: CreateFightPostCommentRequest,
    database: Sql = createDatabaseClient(),
): Promise<FightPostCommentResponse> {
    const post = await loadVisiblePost(userId, postId, database);
    const [rate] = await database<{ n: number }[]>`
        select count(*)::int as n
        from public.fight_post_comments
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
    if (input.parent_id) {
        const [parent] = await database<{ id: string }[]>`
            select id
            from public.fight_post_comments
            where id = ${input.parent_id} and post_id = ${postId}
        `;
        if (!parent) {
            throw new ApiError(
                404,
                ERROR_CODES.not_found,
                "That comment is gone",
            );
        }
    }
    const [created] = await database<{ id: string }[]>`
        insert into public.fight_post_comments (post_id, parent_id, author_id, body)
        values (${postId}, ${input.parent_id ?? null}, ${userId}, ${input.body})
        returning id
    `;
    if (!created) {
        throw new ApiError(
            500,
            ERROR_CODES.db_error,
            "Could not save that comment",
        );
    }
    const mentionIds = await eligibleMentionUserIds(
        database,
        userId,
        [],
        mentionHandlesFromBody(input.body),
        post.fight_id ? [post.fight_id] : [],
    );
    await enqueueMentionNotifications(database, {
        actorId: userId,
        postId,
        commentId: created.id,
        userIds: mentionIds,
        preferredFightId: post.fight_id,
    });
    await enqueueFightFeedCommentNotifications(database, {
        postId,
        commentId: created.id,
        parentId: input.parent_id ?? null,
        actorId: userId,
        skipUserIds: mentionIds,
    });
    const [row] = await database<CommentRow[]>`
        select
            comment.id, comment.post_id, comment.parent_id, comment.body, comment.created_at,
            comment.author_id, profile.handle as author_handle, profile.display_name as author_display_name,
            profile.companion_id as author_companion_id,
            avatar.id as avatar_id, avatar.kind::text as avatar_kind, avatar.purpose::text as avatar_purpose,
            avatar.status::text as avatar_status, avatar.object_path as avatar_object_path,
            avatar.original_filename as avatar_original_filename, avatar.content_type as avatar_content_type,
            avatar.byte_size::text as avatar_byte_size, avatar.width as avatar_width,
            avatar.height as avatar_height, avatar.duration_ms as avatar_duration_ms,
            avatar.sha256 as avatar_sha256, avatar.created_at as avatar_created_at
        from public.fight_post_comments as comment
        join public.profiles as profile
            on profile.id = comment.author_id and profile.deleted_at is null
        left join public.media_objects as avatar
            on avatar.id = profile.avatar_media_id and avatar.status = 'ready'
        where comment.id = ${created.id}
    `;
    if (!row) {
        throw new ApiError(
            500,
            ERROR_CODES.db_error,
            "Could not load that comment",
        );
    }
    const [comment] = await mapComments(userId, [row]);
    if (!comment) {
        throw new ApiError(
            500,
            ERROR_CODES.db_error,
            "Could not load that comment",
        );
    }
    return {
        comment,
        comment_count: await readVisibleCommentCount(userId, postId, database),
    };
}

export async function deleteFightPostComment(
    userId: string,
    postId: string,
    commentId: string,
    database: Sql = createDatabaseClient(),
): Promise<DeleteFightPostCommentResponse> {
    await loadVisiblePost(userId, postId, database);
    const [deleted] = await database<{ id: string }[]>`
        delete from public.fight_post_comments
        where id = ${commentId}
            and post_id = ${postId}
            and author_id = ${userId}
        returning id
    `;
    if (!deleted) {
        throw new ApiError(404, ERROR_CODES.not_found, "Comment not found");
    }
    return {
        deleted: true,
        comment_count: await readVisibleCommentCount(userId, postId, database),
    };
}

export async function reportFightPostComment(
    userId: string,
    postId: string,
    commentId: string,
    input: ReportFightPostCommentRequest,
    database: Sql = createDatabaseClient(),
): Promise<ReportFightPostCommentResponse> {
    await loadVisiblePost(userId, postId, database);
    const [comment] = await database<{ id: string; author_id: string }[]>`
        select id, author_id
        from public.fight_post_comments
        where id = ${commentId} and post_id = ${postId}
    `;
    if (!comment) {
        throw new ApiError(404, ERROR_CODES.not_found, "Comment not found");
    }
    if (comment.author_id === userId) {
        throw new ApiError(
            400,
            ERROR_CODES.validation,
            "You cannot report your own comment",
        );
    }
    await database`
        insert into private.fight_post_comment_reports (comment_id, reporter_id, reason)
        values (${commentId}, ${userId}, ${input.reason})
        on conflict (comment_id, reporter_id) do update set reason = excluded.reason
    `;
    return { reported: true };
}

/** Requires post access and omits hidden or deleted people from the reaction list. */
export async function listFightPostReactionPeople(
    userId: string,
    postId: string,
    query: ListFightPostReactionPeopleQuery,
    database: Sql = createDatabaseClient(),
): Promise<FightPostReactionPeopleResponse> {
    const post = await loadVisiblePost(userId, postId, database);
    const rows = await database`
        select reaction.user_id, reaction.emoji, profile.handle, profile.display_name
        from public.fight_post_reactions as reaction
        join public.profiles as profile
            on profile.id = reaction.user_id and profile.deleted_at is null
        where reaction.post_id = ${postId}
            and (${query.cursor ?? null}::uuid is null or reaction.user_id > ${query.cursor ?? null}::uuid)
            and not exists (
                select 1 from private.feed_blocks as blocked
                where blocked.blocker_id = ${userId}
                    and blocked.blocked_id in (reaction.user_id, ${post.author_id}::uuid)
            )
        order by reaction.user_id
        limit ${query.limit + 1}
    `;
    const people = rows
        .slice(0, query.limit)
        .map((row) => fightPostReactionPersonSchema.parse(row));
    const last = people.at(-1);
    return {
        people,
        next_cursor: rows.length > query.limit && last ? last.user_id : null,
    };
}

export async function setFightPostReaction(
    userId: string,
    postId: string,
    emoji: string,
    database: Sql = createDatabaseClient(),
): Promise<FightPostReactionResponse> {
    await loadVisiblePost(userId, postId, database);
    const [existing] = await database<{ emoji: string }[]>`
        select emoji
        from public.fight_post_reactions
        where post_id = ${postId} and user_id = ${userId}
    `;
    if (existing?.emoji === emoji) {
        await database`
            delete from public.fight_post_reactions
            where post_id = ${postId} and user_id = ${userId}
        `;
    } else {
        await database`
            insert into public.fight_post_reactions (post_id, user_id, emoji)
            values (${postId}, ${userId}, ${emoji})
            on conflict (post_id, user_id) do update
                set emoji = excluded.emoji, created_at = now()
        `;
        await enqueueFightFeedReactionNotifications(database, {
            postId,
            actorId: userId,
        });
    }
    return { reactions: await listPostReactions(userId, postId, database) };
}
