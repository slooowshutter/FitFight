import type { Sql } from "postgres";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    feedActivityItemSchema,
    type FeedActivityResponse,
    type ListFeedActivityQuery,
} from "@/lib/types/feed/feed-activity";

/** Activity is independent of push delivery and restricted to currently visible content. */
export async function listFeedActivity(
    userId: string,
    query: ListFeedActivityQuery,
    database: Sql = createDatabaseClient(),
): Promise<FeedActivityResponse> {
    const rows = await database`
        with my_fights as (
            select f.id, f.name, f.action_text, f.series_id, f.owner_id, m.state
            from public.fights f
            join public.fight_members m on m.fight_id = f.id
            where m.user_id = ${userId} and m.state in ('accepted', 'deferred', 'invited')
        ), visible_posts as (
            select p.id, p.author_id, p.body, p.created_at, channel.id as fight_id,
                channel.name as fight_name
            from public.fight_posts p
            join public.profiles author on author.id = p.author_id and author.deleted_at is null
            join lateral (
                select f.id,
                    coalesce(nullif(nullif(f.name, 'Steps Fight'), ''), nullif(f.action_text, ''), 'Steps Fight') as name
                from my_fights f
                where f.state in ('accepted', 'deferred') and (
                    f.id = p.fight_id
                    or exists (
                        select 1 from public.fight_post_channels c
                        join public.fights original on original.id = c.fight_id
                        where c.post_id = p.id and (
                            c.fight_id = f.id
                            or (f.series_id is not null and original.series_id = f.series_id)
                        )
                    )
                    or exists (
                        select 1 from public.fights original
                        where original.id = p.fight_id
                            and f.series_id is not null and original.series_id = f.series_id
                    )
                )
                order by (f.id = p.fight_id) desc nulls last, f.id
                limit 1
            ) channel on true
            where p.audience = 'fight' and not exists (
                select 1 from private.feed_blocks b
                where (b.blocker_id = ${userId} and b.blocked_id = p.author_id)
                    or (b.blocked_id = ${userId} and b.blocker_id = p.author_id)
            )
        ), events as (
            select 'post:' || p.id::text as id, 'feed_post' as kind, p.created_at as occurred_at,
                p.author_id as actor_id, null::uuid as subject_id, p.fight_id, p.fight_name,
                p.id as post_id, null::uuid as comment_id, left(p.body, 180) as body
            from visible_posts p
            union all
            select 'comment:' || c.id::text,
                case when c.parent_id is null then 'post_comment' else 'comment_reply' end,
                c.created_at, c.author_id, null::uuid, p.fight_id, p.fight_name, p.id, c.id, left(c.body, 180)
            from visible_posts p join public.fight_post_comments c on c.post_id = p.id
            union all
            select 'reaction:' || r.post_id::text || ':' || r.user_id::text, 'post_reaction',
                r.created_at, r.user_id, null::uuid, p.fight_id, p.fight_name, p.id, null::uuid, r.emoji
            from visible_posts p join public.fight_post_reactions r on r.post_id = p.id
            union all
            select 'membership:' || e.id::text, e.state::text, e.occurred_at,
                case when e.state = 'invited' then f.owner_id else e.user_id end,
                case when e.state = 'invited' then e.user_id else null::uuid end,
                f.id, coalesce(nullif(nullif(f.name, 'Steps Fight'), ''), nullif(f.action_text, ''), 'Steps Fight'),
                null::uuid, null::uuid, ''
            from private.fight_membership_events e
            join my_fights f on f.id = e.fight_id
            join public.profiles member on member.id = e.user_id and member.deleted_at is null
            where (f.state in ('accepted', 'deferred') or e.user_id = ${userId})
                and not exists (
                    select 1 from private.feed_blocks b
                    where (b.blocker_id = ${userId} and b.blocked_id = e.user_id)
                        or (b.blocked_id = ${userId} and b.blocker_id = e.user_id)
                )
        )
        select e.id, e.kind,
            to_char(e.occurred_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as occurred_at,
            jsonb_build_object('user_id', actor.id, 'handle', actor.handle) as actor,
            case when subject.id is not null then
                jsonb_build_object('user_id', subject.id, 'handle', subject.handle)
            else null end as subject,
            e.fight_id, e.fight_name, e.post_id, e.comment_id, e.body
        from events e
        join public.profiles actor on actor.id = e.actor_id and actor.deleted_at is null
        left join public.profiles subject on subject.id = e.subject_id and subject.deleted_at is null
        where not exists (
                select 1 from private.feed_blocks b
                where (b.blocker_id = ${userId} and b.blocked_id = e.actor_id)
                    or (b.blocked_id = ${userId} and b.blocker_id = e.actor_id)
            )
            and (
                ${query.cursor === undefined}
                or (coalesce(e.occurred_at, '-infinity'::timestamptz), e.id)
                    -- Text binding avoids the driver's millisecond-only Date serialization.
                    < (coalesce(${query.cursor?.at ?? null}::text::timestamptz, '-infinity'::timestamptz), ${query.cursor?.id ?? ""})
            )
        order by e.occurred_at desc nulls last, e.id desc
        limit ${query.limit + 1}
    `;
    const events = feedActivityItemSchema.array().parse(rows.slice(0, query.limit));
    const last = events.at(-1);
    return {
        events,
        next_cursor: rows.length > query.limit && last
            ? `${last.occurred_at ?? "unknown"}|${last.id}`
            : null,
    };
}
