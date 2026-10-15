import type { Sql, TransactionSql } from "postgres";
import { inviteNotificationAlert } from "@/lib/notifications/notification-copy";
import type { NotificationLocale } from "@/lib/types/notifications/device-installation";
import type {
    NotificationKind,
    NotificationSlot,
} from "@/lib/types/notifications/notification-intent";

const HOUR_MS = 3_600_000;

type MemberCompletion = {
    user_id: string;
    final_steps_complete: boolean;
};

function idempotencyKey(
    fightId: string,
    userId: string,
    kind: NotificationKind,
    slot: NotificationSlot,
): string {
    return `${fightId}:${userId}:${kind}:${slot}`;
}

function routeForFight(fightId: string): string {
    return `/fights/${fightId}`;
}

async function insertNotificationIntents(
    sql: Sql,
    rows: Record<string, string>[],
): Promise<void> {
    if (rows.length === 0) return;
    await sql`
        insert into private.notification_intents (
            idempotency_key, user_id, fight_id, kind, slot,
            not_before, expires_at, route, copy_key
        )
        select row.idempotency_key, row.user_id, row.fight_id, row.kind, row.slot,
            row.not_before::timestamptz, row.expires_at::timestamptz, row.route, row.copy_key
        from jsonb_to_recordset(${sql.json(rows)}::jsonb) as row (
            idempotency_key text,
            user_id uuid,
            fight_id uuid,
            kind text,
            slot text,
            not_before text,
            expires_at text,
            route text,
            copy_key text
        )
        on conflict (idempotency_key) do nothing
    `;
}

export async function insertNotificationIntentsWithAlertBody(
    sql: Sql | TransactionSql,
    rows: Record<string, string>[],
): Promise<void> {
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

export async function enqueueAwaitingFinalSyncNotifications(
    sql: Sql,
    fightId: string,
    endsAt: string,
    members: MemberCompletion[],
): Promise<void> {
    const endsAtMs = Date.parse(endsAt);
    const rows = members.flatMap((member) => [
        {
            idempotency_key: idempotencyKey(fightId, member.user_id, "fight_ended", "t0"),
            user_id: member.user_id,
            fight_id: fightId,
            kind: "fight_ended",
            slot: "t0",
            not_before: new Date(endsAtMs).toISOString(),
            expires_at: new Date(endsAtMs + 2 * HOUR_MS).toISOString(),
            route: routeForFight(fightId),
            copy_key: "fight_ended_everyone",
        },
        ...(!member.final_steps_complete ? [{
            idempotency_key: idempotencyKey(fightId, member.user_id, "final_sync", "t0"),
            user_id: member.user_id,
            fight_id: fightId,
            kind: "final_sync",
            slot: "t0",
            not_before: new Date(endsAtMs).toISOString(),
            expires_at: new Date(endsAtMs + 24 * HOUR_MS).toISOString(),
            route: routeForFight(fightId),
            copy_key: "final_sync",
        }] : []),
    ]);
    await insertNotificationIntents(sql, rows);
}

export async function enqueueFightFinalizedNotifications(
    sql: Sql,
    fightId: string,
    now: Date,
    members: MemberCompletion[],
): Promise<void> {
    const notBefore = now.toISOString();
    const expiresAt = new Date(now.getTime() + 24 * HOUR_MS).toISOString();
    const rows = members.map((member) => ({
        idempotency_key: idempotencyKey(
            fightId,
            member.user_id,
            "fight_finalized",
            "final",
        ),
        user_id: member.user_id,
        fight_id: fightId,
        kind: "fight_finalized",
        slot: "final",
        not_before: notBefore,
        expires_at: expiresAt,
        route: routeForFight(fightId),
        copy_key: "fight_finalized",
    }));
    await insertNotificationIntents(sql, rows);
}

/** One reminder per person and month, however many friend rounds they are behind in. */
export async function enqueueFriendsSyncNotifications(
    sql: Sql,
    fightId: string,
): Promise<void> {
    await sql`
        insert into private.notification_intents (
            idempotency_key, user_id, fight_id, kind, slot,
            not_before, expires_at, route, copy_key
        )
        select member.user_id || ':friends_sync:' || to_char(fight.starts_at at time zone fight.time_zone, 'YYYY-MM'),
            member.user_id, fight.id, 'friends_sync', 't0',
            -- West of the round's zone the last local day is not over at ends_at. 09:00 local on the 1st
            -- avoids night pushes and stays inside the 24h grace down to UTC-12.
            greatest(
                fight.ends_at,
                ((fight.ends_at at time zone fight.time_zone)::date + time '09:00')
                    at time zone coalesce(profile.time_zone, fight.time_zone)
            ),
            fight.ends_at + fight.final_sync_grace_seconds * interval '1 second',
            '/fights/' || fight.id || '?friends=1', 'friends_sync'
        from public.fights fight
        join public.fight_members member on member.fight_id = fight.id and member.state = 'accepted'
        join public.profiles profile on profile.id = member.user_id
        where fight.id = ${fightId} and fight.friends and not member.final_steps_complete
        on conflict (idempotency_key) do nothing
    `;
}

/** Each member's results push waits for the last of their friend rounds that month to finalize. */
export async function enqueueFriendsResultsNotifications(
    sql: Sql,
    fightId: string,
    now: Date,
): Promise<void> {
    // NOTE: a month's rounds finalize in separate transactions. Serializing them lets the last one see the others final.
    await sql`
        select pg_advisory_xact_lock(hashtextextended(
            'fitfight:friends_results:' || to_char(starts_at at time zone time_zone, 'YYYY-MM'), 0
        ))
        from public.fights where id = ${fightId}
    `;
    await sql`
        insert into private.notification_intents (
            idempotency_key, user_id, fight_id, kind, slot,
            not_before, expires_at, route, copy_key
        )
        select member.user_id || ':friends_results:' || month.key,
            member.user_id, fight.id, 'friends_results', 'final',
            ${now.toISOString()}::timestamptz, ${new Date(now.getTime() + 24 * HOUR_MS).toISOString()}::timestamptz,
            '/fights/' || fight.id || '?friends=1', 'friends_results'
        from public.fights fight
        cross join lateral (
            select to_char(fight.starts_at at time zone fight.time_zone, 'YYYY-MM') as key
        ) month
        join public.fight_members member on member.fight_id = fight.id and member.state = 'accepted'
        where fight.id = ${fightId} and fight.friends
            and not exists (
                select 1 from public.fights round
                join public.fight_members mine on mine.fight_id = round.id
                    and mine.user_id = member.user_id and mine.state = 'accepted'
                where round.friends and round.state not in ('final', 'cancelled')
                    and to_char(round.starts_at at time zone round.time_zone, 'YYYY-MM') = month.key
            )
        on conflict (idempotency_key) do nothing
    `;
}

export async function supersedeGraceNotifications(
    sql: Sql,
    fightId: string,
): Promise<void> {
    await sql`
        update private.notification_intents
        set status = 'skipped',
            skip_reason = 'superseded',
            processed_at = now()
        where fight_id = ${fightId}
            and status = 'pending'
            and (slot in ('t12', 't18', 't23') or kind = 'final_sync')
    `;
}

export async function skipGraceNotificationsForMember(
    sql: Sql,
    fightId: string,
    userId: string,
): Promise<void> {
    await sql`
        update private.notification_intents
        set status = 'skipped',
            skip_reason = 'already_complete',
            processed_at = now()
        where fight_id = ${fightId}
            and user_id = ${userId}
            and status = 'pending'
            and (slot in ('t12', 't18', 't23') or kind = 'final_sync')
    `;
}

export async function enqueueFightInviteNotifications(
    sql: Sql | TransactionSql,
    input: {
        fightId: string;
        fightName: string;
        actorName: string;
        userIds: string[];
        now?: Date;
    },
): Promise<void> {
    if (input.userIds.length === 0) return;
    const now = input.now ?? new Date();
    const notBefore = now.toISOString();
    const expiresAt = new Date(now.getTime() + 24 * HOUR_MS).toISOString();
    const recipients = await sql<
        { user_id: string; locale: string | null }[]
    >`
        select distinct on (profile.id)
            profile.id as user_id,
            installation.locale
        from public.profiles as profile
        left join private.device_installations as installation
            on installation.user_id = profile.id
            and installation.revoked_at is null
        where profile.id in ${sql(input.userIds)}
            and profile.deleted_at is null
            and not exists (
                select 1 from private.notification_preferences prefs
                where prefs.user_id = profile.id and (not prefs.enabled or not prefs.fight_invite)
            )
        order by profile.id, installation.last_registered_at desc nulls last
    `;
    const rows = recipients.map((recipient) => {
        const locale: NotificationLocale =
            recipient.locale === "fr" ? "fr" : "en";
        return {
            idempotency_key: idempotencyKey(
                input.fightId,
                recipient.user_id,
                "fight_invite",
                "event",
            ),
            user_id: recipient.user_id,
            fight_id: input.fightId,
            kind: "fight_invite" as const,
            slot: "event" as const,
            not_before: notBefore,
            expires_at: expiresAt,
            route: routeForFight(input.fightId),
            copy_key: "fight_invite" as const,
            alert_body: inviteNotificationAlert(
                input.actorName,
                input.fightName,
                locale,
            ).body,
        };
    });
    await insertNotificationIntentsWithAlertBody(sql, rows);
}
