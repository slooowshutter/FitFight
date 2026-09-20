import type { Sql } from "postgres";
import { sendApnsAlert } from "@/lib/apns/apns-client";
import { isApnsConfigured, readApnsEnvironment } from "@/lib/apns/apns-config";
import { notificationDeliveryRowSchema } from "@/lib/types/notifications/notification-delivery";
import type { NotificationKind } from "@/lib/types/notifications/notification-intent";
import { defaultNotificationPreferences, type NotificationPreferences } from "@/lib/types/notifications/notification-preferences";
import { readNotificationContent } from "./notification-content-supabase-query";
import {
    decryptInstallationToken,
    readActiveDeviceInstallations,
    revokeDeviceInstallation,
} from "./device-installations-supabase-query";

const BATCH = 50;

export type ProcessNotificationOutboxResult = {
    checked: number;
    sent: number;
    skipped: number;
    failed: number;
    expired: number;
    pending: number;
};

function isMuted(kind: NotificationKind, prefs: NotificationPreferences): boolean {
    if (!prefs.enabled) return true;
    switch (kind) {
        case "grace_reminder":
        case "feed_post":
        case "post_reaction":
            return true;
        case "social_digest":
            return !prefs.feed_post && !prefs.post_reaction;
        default:
            return !prefs[kind];
    }
}

async function markIntent(
    sql: Sql,
    intentId: string,
    status: "skipped" | "sent" | "failed" | "expired",
    skipReason?: string,
): Promise<void> {
    await sql`
        update private.notification_intents
        set status = ${status},
            skip_reason = ${skipReason ?? null},
            processed_at = now()
        where id = ${intentId}
    `;
}

async function recordDelivery(
    sql: Sql,
    intentId: string,
    installationId: string,
    attempt: number,
    httpStatus: number | null,
    reason: string | null,
): Promise<void> {
    await sql`
        insert into private.notification_deliveries (
            intent_id, installation_id, attempt, apns_http_status, apns_reason
        ) values (
            ${intentId}, ${installationId}, ${attempt}, ${httpStatus}, ${reason}
        )
    `;
}

export async function processNotificationOutbox(
    now: Date = new Date(),
    database: Sql,
): Promise<ProcessNotificationOutboxResult> {
    const result: ProcessNotificationOutboxResult = {
        checked: 0,
        sent: 0,
        skipped: 0,
        failed: 0,
        expired: 0,
        pending: 0,
    };
    const nowIso = now.toISOString();

    await database`
        update private.notification_intents
        set status = 'expired',
            processed_at = now()
        where status = 'pending'
            and expires_at <= ${nowIso}::timestamptz
    `;

    const rows = notificationDeliveryRowSchema.array().parse(await database`
        with picked as (
            select intent.id
            from private.notification_intents as intent
            where intent.status = 'pending'
                and intent.kind not in ('feed_post', 'post_reaction')
                and intent.not_before <= ${nowIso}::timestamptz
                and intent.expires_at > ${nowIso}::timestamptz
                and (
                    intent.processed_at is null
                    or intent.processed_at < ${nowIso}::timestamptz - interval '15 minutes'
                )
            order by intent.not_before, intent.id
            limit ${BATCH}
            for update skip locked
        ),
        claimed as (
            update private.notification_intents as intent
            set processed_at = ${nowIso}::timestamptz
            from picked
            where intent.id = picked.id
                and intent.status = 'pending'
            returning intent.id, intent.user_id, intent.fight_id, intent.kind, intent.slot,
                intent.route, intent.copy_key, intent.alert_body
        )
        select claimed.id, claimed.user_id, claimed.fight_id, claimed.kind, claimed.slot,
            claimed.route, claimed.copy_key, claimed.alert_body, fight.state::text as fight_state,
            member.final_steps_complete, member.state::text as member_state,
            coalesce(fight.name, '') as fight_name, owner.handle as owner_handle,
            fight.ends_at, fight.ends_at + fight.final_sync_grace_seconds * interval '1 second' as sync_deadline,
            coalesce(profile.time_zone, 'UTC') as time_zone,
            to_jsonb(prefs) as preferences
        from claimed
        left join public.fights as fight on fight.id = claimed.fight_id
        left join public.fight_members as member
            on member.fight_id = claimed.fight_id
            and member.user_id = claimed.user_id
        join public.profiles profile on profile.id = claimed.user_id and profile.deleted_at is null
        left join public.profiles owner on owner.id = fight.owner_id and owner.deleted_at is null
        left join private.notification_preferences as prefs
            on prefs.user_id = claimed.user_id
    `);

    result.checked = rows.length;
    if (rows.length === 0) {
        return result;
    }

    const apnsConfigured = isApnsConfigured();
    const apnsEnvironment = readApnsEnvironment();

    for (const row of rows) {
        const intent = row;
        const prefs = { ...defaultNotificationPreferences, ...row.preferences };

        if (intent.kind !== "social_digest" && (row.fight_state === "cancelled" || row.fight_state === null)) {
            await markIntent(database, intent.id, "skipped", "fight_cancelled");
            result.skipped += 1;
            continue;
        }

        if (isMuted(intent.kind, prefs)) {
            await markIntent(database, intent.id, "skipped", "muted");
            result.skipped += 1;
            continue;
        }

        if (
            intent.kind === "final_sync" &&
            (row.final_steps_complete === true || row.fight_state !== "awaiting_final_sync")
        ) {
            await markIntent(
                database,
                intent.id,
                "skipped",
                "already_complete",
            );
            result.skipped += 1;
            continue;
        }

        const social = ["social_digest", "post_comment", "comment_reply", "mention"].includes(intent.kind);
        if ((!social && (intent.kind === "fight_invite" ? row.member_state !== "invited" : row.member_state !== "accepted"))
            || ((intent.kind === "ending_24h" || intent.kind === "ending_week") && row.fight_state !== "live")
            || (intent.kind === "fight_ended" && !row.final_steps_complete && prefs.final_sync)) {
            await markIntent(database, intent.id, "skipped", "superseded");
            result.skipped += 1;
            continue;
        }

        if (!apnsConfigured || !apnsEnvironment) {
            result.pending += 1;
            continue;
        }

        const installations = await readActiveDeviceInstallations(
            intent.user_id,
            database,
        );
        if (installations.length === 0) {
            await markIntent(database, intent.id, "skipped", "no_token");
            result.skipped += 1;
            continue;
        }

        const content = await readNotificationContent(row, installations[0].locale === "fr" ? "fr" : "en", database);
        if (!content) {
            await markIntent(database, intent.id, "skipped", "superseded");
            result.skipped += 1;
            continue;
        }
        let delivered = false;
        let retryLater = false;
        let invalidProviderToken = false;

        for (const [index, installation] of installations.entries()) {
            const attempt = index + 1;
            let deviceToken: string;
            try {
                deviceToken = decryptInstallationToken(installation);
            } catch {
                await revokeDeviceInstallation(
                    installation.id,
                    "decrypt_failed",
                    database,
                );
                continue;
            }

            const sendResult = await sendApnsAlert({
                deviceToken,
                environment: installation.apns_environment,
                topic: apnsEnvironment.topic,
                title: content.title,
                body: content.body,
                route: content.route,
                threadId: content.threadId,
                collapseId: intent.id,
                expiresAt: Math.floor(now.getTime() / 1000) + 3600,
                imageUrl: content.imageUrl ?? undefined,
            });

            await recordDelivery(
                database,
                intent.id,
                installation.id,
                attempt,
                sendResult.httpStatus,
                sendResult.reason,
            );

            if (sendResult.invalidProviderToken) {
                invalidProviderToken = true;
                break;
            }
            if (sendResult.retryLater) {
                retryLater = true;
                break;
            }
            if (sendResult.unregistered) {
                await revokeDeviceInstallation(
                    installation.id,
                    sendResult.reason ?? "unregistered",
                    database,
                );
                continue;
            }
            if (sendResult.httpStatus === 200) {
                delivered = true;
                break;
            }
        }

        if (invalidProviderToken) {
            result.pending += 1;
            continue;
        }
        if (retryLater) {
            result.pending += 1;
            continue;
        }
        if (delivered) {
            await markIntent(database, intent.id, "sent");
            result.sent += 1;
            continue;
        }

        await markIntent(database, intent.id, "skipped", "no_token");
        result.skipped += 1;
    }

    return result;
}
