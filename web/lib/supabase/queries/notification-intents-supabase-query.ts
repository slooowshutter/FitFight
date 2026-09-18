import type { Sql, TransactionSql } from "postgres";
import { inviteNotificationAlert } from "@/lib/notifications/notification-copy";
import type { NotificationLocale } from "@/lib/types/notifications/device-installation";
import type {
    NotificationCopyKey,
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

export async function enqueueAwaitingFinalSyncNotifications(
    sql: Sql,
    fightId: string,
    endsAt: string,
    members: MemberCompletion[],
): Promise<void> {
    const endsAtMs = Date.parse(endsAt);
    const rows = members.flatMap((member) => {
        const t0Copy: NotificationCopyKey = member.final_steps_complete
            ? "fight_ended_everyone"
            : "fight_ended_sync";
        return [
            {
                idempotency_key: idempotencyKey(
                    fightId,
                    member.user_id,
                    "fight_ended",
                    "t0",
                ),
                user_id: member.user_id,
                fight_id: fightId,
                kind: "fight_ended" as const,
                slot: "t0" as const,
                not_before: new Date(endsAtMs).toISOString(),
                expires_at: new Date(endsAtMs + 2 * HOUR_MS).toISOString(),
                route: routeForFight(fightId),
                copy_key: t0Copy,
            },
            {
                idempotency_key: idempotencyKey(
                    fightId,
                    member.user_id,
                    "grace_reminder",
                    "t12",
                ),
                user_id: member.user_id,
                fight_id: fightId,
                kind: "grace_reminder" as const,
                slot: "t12" as const,
                not_before: new Date(endsAtMs + 12 * HOUR_MS).toISOString(),
                expires_at: new Date(endsAtMs + 14 * HOUR_MS).toISOString(),
                route: routeForFight(fightId),
                copy_key: "grace_12h" as const,
            },
            {
                idempotency_key: idempotencyKey(
                    fightId,
                    member.user_id,
                    "grace_reminder",
                    "t18",
                ),
                user_id: member.user_id,
                fight_id: fightId,
                kind: "grace_reminder" as const,
                slot: "t18" as const,
                not_before: new Date(endsAtMs + 18 * HOUR_MS).toISOString(),
                expires_at: new Date(endsAtMs + 20 * HOUR_MS).toISOString(),
                route: routeForFight(fightId),
                copy_key: "grace_6h" as const,
            },
            {
                idempotency_key: idempotencyKey(
                    fightId,
                    member.user_id,
                    "grace_reminder",
                    "t23",
                ),
                user_id: member.user_id,
                fight_id: fightId,
                kind: "grace_reminder" as const,
                slot: "t23" as const,
                not_before: new Date(endsAtMs + 23 * HOUR_MS).toISOString(),
                expires_at: new Date(endsAtMs + 24 * HOUR_MS).toISOString(),
                route: routeForFight(fightId),
                copy_key: "grace_1h" as const,
            },
        ];
    });
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
            and slot in ('t12', 't18', 't23')
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
            and slot in ('t12', 't18', 't23')
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
        select distinct on (profile.user_id)
            profile.user_id,
            installation.locale
        from public.profiles as profile
        left join private.device_installations as installation
            on installation.user_id = profile.user_id
            and installation.revoked_at is null
        where profile.user_id in ${sql(input.userIds)}
            and profile.deleted_at is null
        order by profile.user_id, installation.last_registered_at desc nulls last
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
