import type { Sql } from "postgres";
import {
    mentionNotificationAlert,
    socialNotificationAlert,
} from "@/lib/notifications/notification-copy";
import type { NotificationLocale } from "@/lib/types/notifications/device-installation";
import type {
    NotificationCopyKey,
    NotificationKind,
} from "@/lib/types/notifications/notification-intent";

const HOUR_MS = 3_600_000;

type SocialKind = Extract<
    NotificationKind,
    "feed_post" | "post_comment" | "comment_reply" | "post_reaction" | "mention"
>;

type Recipient = {
    userId: string;
    kind: SocialKind;
    eventId: string;
    fightId: string;
    copyKey?: NotificationCopyKey;
};

type RecipientRow = {
    user_id: string;
    locale: string | null;
    feed_post: boolean | null;
    post_comment: boolean | null;
    comment_reply: boolean | null;
    post_reaction: boolean | null;
};

function localeFor(value: string | null): NotificationLocale {
    return value === "fr" ? "fr" : "en";
}

function preferenceOn(kind: SocialKind, row: RecipientRow): boolean {
    switch (kind) {
        case "feed_post":
            return row.feed_post !== false;
        case "post_comment":
            return row.post_comment !== false;
        case "comment_reply":
            return row.comment_reply !== false;
        case "post_reaction":
            return row.post_reaction !== false;
        case "mention":
            return true;
        default: {
            const _exhaustive: never = kind;
            return _exhaustive;
        }
    }
}

async function actorName(sql: Sql, actorId: string): Promise<string> {
    const [profile] = await sql<{ handle: string; display_name: string }[]>`
        select handle, display_name
        from public.profiles
        where id = ${actorId}
            and deleted_at is null
    `;
    if (!profile) return "";
    const display = profile.display_name.replace(/\s+/g, " ").trim();
    return display.length > 0 ? display : profile.handle;
}

async function recipientRows(
    sql: Sql,
    actorId: string,
    userIds: string[],
): Promise<RecipientRow[]> {
    if (userIds.length === 0) return [];
    return sql<RecipientRow[]>`
        select distinct on (profile.id)
            profile.id as user_id,
            installation.locale,
            prefs.feed_post,
            prefs.post_comment,
            prefs.comment_reply,
            prefs.post_reaction
        from public.profiles as profile
        left join private.notification_preferences as prefs
            on prefs.user_id = profile.id
        left join private.device_installations as installation
            on installation.user_id = profile.id
            and installation.revoked_at is null
        where profile.id in ${sql(userIds)}
            and profile.deleted_at is null
            and not exists (
                select 1
                from private.feed_blocks as blocked
                where (blocked.blocker_id = profile.id and blocked.blocked_id = ${actorId})
                    or (blocked.blocker_id = ${actorId} and blocked.blocked_id = profile.id)
            )
        order by profile.id, installation.last_registered_at desc nulls last
    `;
}

async function accessibleFightByUser(
    sql: Sql,
    userIds: string[],
    postId: string,
    preferredFightId: string | null,
): Promise<Map<string, string>> {
    if (userIds.length === 0) return new Map();
    const rows = await sql<{ user_id: string; fight_id: string }[]>`
        select distinct on (member.user_id)
            member.user_id,
            member.fight_id
        from public.fight_members as member
        where member.user_id in ${sql(userIds)}
            and member.state in ('accepted', 'deferred')
            and (
                member.fight_id = ${preferredFightId}
                or exists (
                    select 1
                    from public.fight_post_channels as channel
                    where channel.post_id = ${postId}
                        and channel.fight_id = member.fight_id
                )
                or exists (
                    select 1
                    from public.fights as posted
                    join public.fights as sibling
                        on sibling.series_id = posted.series_id
                    where posted.series_id is not null
                        and sibling.id = member.fight_id
                        and (
                            posted.id = ${preferredFightId}
                            or exists (
                                select 1
                                from public.fight_post_channels as channel
                                where channel.post_id = ${postId}
                                    and channel.fight_id = posted.id
                            )
                        )
                )
            )
        order by member.user_id, (member.fight_id = ${preferredFightId}) desc nulls last, member.fight_id
    `;
    return new Map(rows.map((row) => [row.user_id, row.fight_id]));
}

async function insertSocialIntents(
    sql: Sql,
    actorId: string,
    actor: string,
    recipients: Recipient[],
    postId: string,
    commentId?: string,
): Promise<void> {
    const unique = new Map<string, Recipient>();
    for (const recipient of recipients) {
        if (recipient.userId === actorId) continue;
        unique.set(`${recipient.userId}:${recipient.kind}`, recipient);
    }
    const wanted = [...unique.values()];
    if (wanted.length === 0) return;
    const rowsByUser = new Map(
        (
            await recipientRows(sql, actorId, [
                ...new Set(wanted.map((row) => row.userId)),
            ])
        ).map((row) => [row.user_id, row]),
    );
    const now = Date.now();
    const notBefore = new Date(now).toISOString();
    const expiresAt = new Date(now + 24 * HOUR_MS).toISOString();
    const rows = wanted.flatMap((recipient) => {
        const row = rowsByUser.get(recipient.userId);
        if (!row || !preferenceOn(recipient.kind, row)) return [];
        const locale = localeFor(row.locale);
        const alert =
            recipient.kind === "mention"
                ? mentionNotificationAlert(
                      commentId ? "comment" : "post",
                      actor,
                      locale,
                  )
                : socialNotificationAlert(recipient.kind, actor, locale);
        return [
            {
                idempotency_key: `${recipient.userId}:${recipient.kind}:${recipient.eventId}`,
                user_id: recipient.userId,
                fight_id: recipient.fightId,
                kind: recipient.kind,
                slot: "event",
                not_before: notBefore,
                expires_at: expiresAt,
                route: `/fights/${recipient.fightId}?post=${postId}${commentId ? `&comment=${commentId}` : ""}`,
                copy_key:
                    recipient.copyKey ??
                    (recipient.kind === "mention"
                        ? "mention_post"
                        : recipient.kind),
                alert_body: alert.body,
            },
        ];
    });
    if (rows.length === 0) return;
    await sql`
        insert into private.notification_intents (
            idempotency_key, user_id, fight_id, kind, slot,
            not_before, expires_at, route, copy_key, alert_body
        )
        select row.idempotency_key, row.user_id, row.fight_id, row.kind, row.slot,
            row.not_before::timestamptz, row.expires_at::timestamptz, row.route, row.copy_key, row.alert_body
        from jsonb_to_recordset(${sql.json(rows)}::jsonb) as row (
            idempotency_key text,
            user_id uuid,
            fight_id uuid,
            kind text,
            slot text,
            not_before text,
            expires_at text,
            route text,
            copy_key text,
            alert_body text
        )
        on conflict (idempotency_key) do nothing
    `;
}

export async function enqueueFightFeedPostNotifications(
    sql: Sql,
    input: {
        fightId: string;
        postId: string;
        actorId: string;
        skipUserIds?: string[];
    },
): Promise<void> {
    const members = await sql<{ user_id: string; fight_id: string }[]>`
        select distinct on (member.user_id)
            member.user_id,
            member.fight_id
        from public.fight_members as member
        where member.state in ('accepted', 'deferred')
            and member.user_id <> ${input.actorId}
            and (
                member.fight_id = ${input.fightId}
                or exists (
                    select 1
                    from public.fights as posted
                    join public.fights as sibling
                        on sibling.series_id = posted.series_id
                    where posted.id = ${input.fightId}
                        and posted.series_id is not null
                        and sibling.id = member.fight_id
                )
            )
        order by member.user_id, (member.fight_id = ${input.fightId}) desc, member.fight_id
    `;
    await insertSocialIntents(
        sql,
        input.actorId,
        await actorName(sql, input.actorId),
        members
            .filter(
                (member) => !(input.skipUserIds ?? []).includes(member.user_id),
            )
            .map((member) => ({
                userId: member.user_id,
                kind: "feed_post" as const,
                eventId: input.postId,
                fightId: member.fight_id,
            })),
        input.postId,
    );
}

export async function enqueueFightFeedCommentNotifications(
    sql: Sql,
    input: {
        postId: string;
        commentId: string;
        parentId: string | null;
        actorId: string;
        skipUserIds?: string[];
    },
): Promise<void> {
    const [post] = await sql<{ fight_id: string | null; author_id: string }[]>`
        select fight_id, author_id
        from public.fight_posts
        where id = ${input.postId}
    `;
    if (!post) return;
    const wanted: Array<Omit<Recipient, "fightId">> = [];
    if (input.parentId) {
        const [parent] = await sql<{ author_id: string }[]>`
            select author_id
            from public.fight_post_comments
            where id = ${input.parentId}
                and post_id = ${input.postId}
        `;
        if (parent && parent.author_id !== input.actorId) {
            wanted.push({
                userId: parent.author_id,
                kind: "comment_reply",
                eventId: input.commentId,
            });
        }
    }
    if (
        post.author_id !== input.actorId &&
        !wanted.some((recipient) => recipient.userId === post.author_id)
    ) {
        wanted.push({
            userId: post.author_id,
            kind: "post_comment",
            eventId: input.commentId,
        });
    }
    const skipped = new Set(input.skipUserIds ?? []);
    const remaining = wanted.filter(
        (recipient) => !skipped.has(recipient.userId),
    );
    const fights = await accessibleFightByUser(
        sql,
        remaining.map((recipient) => recipient.userId),
        input.postId,
        post.fight_id,
    );
    await insertSocialIntents(
        sql,
        input.actorId,
        await actorName(sql, input.actorId),
        remaining.flatMap((recipient) => {
            const fightId = fights.get(recipient.userId);
            return fightId ? [{ ...recipient, fightId }] : [];
        }),
        input.postId,
        input.commentId,
    );
}

export async function enqueueFightFeedReactionNotifications(
    sql: Sql,
    input: { postId: string; actorId: string },
): Promise<void> {
    const [post] = await sql<{ fight_id: string | null; author_id: string }[]>`
        select fight_id, author_id
        from public.fight_posts
        where id = ${input.postId}
    `;
    if (!post || post.author_id === input.actorId) return;
    const fightId = (
        await accessibleFightByUser(
            sql,
            [post.author_id],
            input.postId,
            post.fight_id,
        )
    ).get(post.author_id);
    if (!fightId) return;
    await insertSocialIntents(
        sql,
        input.actorId,
        await actorName(sql, input.actorId),
        [
            {
                userId: post.author_id,
                kind: "post_reaction",
                eventId: `${input.postId}:${input.actorId}`,
                fightId,
            },
        ],
        input.postId,
    );
}

const mentionHandlePattern = /(^|[^a-zA-Z0-9_])@([a-zA-Z0-9_]{2,30})/g;

export function mentionHandlesFromBody(body: string): string[] {
    const handles: string[] = [];
    const seen = new Set<string>();
    for (const match of body.matchAll(mentionHandlePattern)) {
        const handle = match[2].toLowerCase();
        if (seen.has(handle)) continue;
        seen.add(handle);
        handles.push(handle);
        if (handles.length === 20) break;
    }
    return handles;
}

export async function eligibleMentionUserIds(
    sql: Sql,
    actorId: string,
    taggedIds: string[],
    handles: string[],
    fightIds: string[],
): Promise<string[]> {
    const uniqueTags = [...new Set(taggedIds)].filter((id) => id !== actorId);
    const uniqueHandles = [
        ...new Set(handles.map((handle) => handle.toLowerCase())),
    ];
    if (uniqueTags.length === 0 && uniqueHandles.length === 0) return [];
    const tagIds = uniqueTags.length > 0 ? uniqueTags : [actorId];
    const handleValues = uniqueHandles.length > 0 ? uniqueHandles : ["_"];
    const rows =
        fightIds.length > 0
            ? await sql<{ user_id: string }[]>`
                select distinct profile.id as user_id
                from public.profiles as profile
                join public.fight_members as membership
                    on membership.user_id = profile.id
                    and membership.state in ('accepted', 'deferred')
                    and membership.fight_id in ${sql(fightIds)}
                where profile.deleted_at is null
                    and profile.id <> ${actorId}
                    and (
                        (${uniqueTags.length > 0}::boolean and profile.id in ${sql(tagIds)})
                        or (${uniqueHandles.length > 0}::boolean and profile.handle in ${sql(handleValues)})
                    )
                    and exists (
                        select 1
                        from public.fight_members as done_me
                        join public.fight_members as done_them
                            on done_them.fight_id = done_me.fight_id
                        join public.fights as done_fight
                            on done_fight.id = done_me.fight_id
                        where done_me.user_id = ${actorId}
                            and done_them.user_id = profile.id
                            and done_me.state = 'accepted'
                            and done_them.state = 'accepted'
                            and done_fight.state = 'final'
                    )
                limit 20
            `
            : await sql<{ user_id: string }[]>`
                select distinct them.user_id
                from public.fight_members as me
                join public.fight_members as them
                    on them.fight_id = me.fight_id
                join public.fights as fight
                    on fight.id = me.fight_id
                join public.profiles as profile
                    on profile.id = them.user_id
                    and profile.deleted_at is null
                where me.user_id = ${actorId}
                    and them.user_id <> ${actorId}
                    and me.state = 'accepted'
                    and them.state = 'accepted'
                    and fight.state = 'final'
                    and (
                        (${uniqueTags.length > 0}::boolean and them.user_id in ${sql(tagIds)})
                        or (${uniqueHandles.length > 0}::boolean and profile.handle in ${sql(handleValues)})
                    )
                limit 20
            `;
    return rows.map((row) => row.user_id);
}

export async function enqueueMentionNotifications(
    sql: Sql,
    input: {
        actorId: string;
        postId: string;
        commentId?: string;
        userIds: string[];
        preferredFightId: string | null;
    },
): Promise<void> {
    const unique = [...new Set(input.userIds)].filter(
        (userId) => userId !== input.actorId,
    );
    if (unique.length === 0) return;
    const fights = await accessibleFightByUser(
        sql,
        unique,
        input.postId,
        input.preferredFightId,
    );
    const missing = unique.filter((userId) => !fights.has(userId));
    if (missing.length > 0) {
        const fallbacks = await sql<{ user_id: string; fight_id: string }[]>`
            select distinct on (member.user_id)
                member.user_id,
                member.fight_id
            from public.fight_members as member
            where member.user_id in ${sql(missing)}
                and member.state in ('accepted', 'deferred')
            order by member.user_id, member.fight_id
        `;
        for (const row of fallbacks) {
            fights.set(row.user_id, row.fight_id);
        }
    }
    await insertSocialIntents(
        sql,
        input.actorId,
        await actorName(sql, input.actorId),
        unique.flatMap((userId) => {
            const fightId = fights.get(userId);
            if (!fightId) return [];
            return [
                {
                    userId,
                    kind: "mention" as const,
                    eventId: input.commentId ?? input.postId,
                    fightId,
                    copyKey: input.commentId
                        ? "mention_comment"
                        : "mention_post",
                },
            ];
        }),
        input.postId,
        input.commentId,
    );
}
