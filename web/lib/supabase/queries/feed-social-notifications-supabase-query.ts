import type { Sql } from "postgres";
import { socialNotificationAlert } from "@/lib/notifications/notification-copy";
import type { NotificationLocale } from "@/lib/types/notifications/device-installation";
import type { NotificationKind } from "@/lib/types/notifications/notification-intent";

const HOUR_MS = 3_600_000;

type SocialKind = Extract<
    NotificationKind,
    "feed_post" | "post_comment" | "comment_reply" | "post_reaction"
>;

type Recipient = {
    userId: string;
    kind: SocialKind;
    eventId: string;
    fightId: string;
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
        where user_id = ${actorId}
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
        select distinct on (profile.user_id)
            profile.user_id,
            installation.locale,
            prefs.feed_post,
            prefs.post_comment,
            prefs.comment_reply,
            prefs.post_reaction
        from public.profiles as profile
        left join private.notification_preferences as prefs
            on prefs.user_id = profile.user_id
        left join private.device_installations as installation
            on installation.user_id = profile.user_id
            and installation.revoked_at is null
        where profile.user_id in ${sql(userIds)}
            and profile.deleted_at is null
            and not exists (
                select 1
                from private.feed_blocks as blocked
                where (blocked.blocker_id = profile.user_id and blocked.blocked_id = ${actorId})
                    or (blocked.blocker_id = ${actorId} and blocked.blocked_id = profile.user_id)
            )
        order by profile.user_id, installation.last_registered_at desc nulls last
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
                copy_key: recipient.kind,
                alert_body: socialNotificationAlert(
                    recipient.kind,
                    actor,
                    locale,
                ).body,
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
    input: { fightId: string; postId: string; actorId: string },
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
        members.map((member) => ({
            userId: member.user_id,
            kind: "feed_post",
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
    const fights = await accessibleFightByUser(
        sql,
        wanted.map((recipient) => recipient.userId),
        input.postId,
        post.fight_id,
    );
    await insertSocialIntents(
        sql,
        input.actorId,
        await actorName(sql, input.actorId),
        wanted.flatMap((recipient) => {
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
