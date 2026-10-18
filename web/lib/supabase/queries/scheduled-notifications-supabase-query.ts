import type { Sql } from "postgres";
import {
    digestCandidateSchema,
    digestEventSchema,
} from "@/lib/types/notifications/scheduled-notifications";

/** The same clock runs from the hosted scheduler and foreground maintenance. */
export async function enqueueScheduledNotifications(database: Sql, now: Date): Promise<void> {
    const at = now.toISOString();
    await database`
        insert into private.notification_intents (
            idempotency_key, user_id, fight_id, kind, slot,
            not_before, expires_at, route, copy_key
        )
        select fight.id || ':' || member.user_id || ':' || reminder.kind,
            member.user_id, fight.id, reminder.kind, reminder.slot,
            fight.ends_at - reminder.notice,
            least(fight.ends_at, fight.ends_at - reminder.notice + interval '2 hours'),
            '/fights/' || fight.id, reminder.kind
        from public.fights fight
        join public.fight_members member on member.fight_id = fight.id and member.state = 'accepted'
            and member.user_id is distinct from fight.host_id
        left join private.notification_preferences prefs on prefs.user_id = member.user_id
        cross join (values
            ('ending_24h', 'before_24h', interval '24 hours'),
            ('ending_week', 'before_week', interval '7 days')
        ) reminder(kind, slot, notice)
        where fight.state = 'live' and not fight.friends
            and coalesce(prefs.enabled, true)
            and case when reminder.kind = 'ending_24h' then coalesce(prefs.ending_24h, true)
                else coalesce(prefs.ending_week, false) end
            and (reminder.kind <> 'ending_week' or (
                (fight.ends_at at time zone fight.time_zone)::date
                - (fight.starts_at at time zone fight.time_zone)::date = 30
            ))
            and fight.ends_at - reminder.notice > fight.starts_at
            and ${at}::timestamptz >= fight.ends_at - reminder.notice
            and ${at}::timestamptz < least(fight.ends_at, fight.ends_at - reminder.notice + interval '2 hours')
        on conflict (idempotency_key) do nothing
    `;

    // An older backend may have already moved the fight into its final-sync window.
    await database`
        insert into private.notification_intents (
            idempotency_key, user_id, fight_id, kind, slot, not_before, expires_at, route, copy_key
        )
        select fight.id || ':' || member.user_id || ':final_sync:t0',
            member.user_id, fight.id, 'final_sync', 't0', ${at}::timestamptz,
            fight.ends_at + fight.final_sync_grace_seconds * interval '1 second',
            '/fights/' || fight.id, 'final_sync'
        from public.fights fight
        join public.fight_members member on member.fight_id = fight.id and member.state = 'accepted'
            and member.user_id is distinct from fight.host_id
        left join private.notification_preferences prefs on prefs.user_id = member.user_id
        where fight.state = 'awaiting_final_sync' and not fight.friends and not member.final_steps_complete
            and coalesce(prefs.enabled, true) and coalesce(prefs.final_sync, true)
            and fight.ends_at + fight.final_sync_grace_seconds * interval '1 second' > ${at}::timestamptz
            and not exists (
                select 1 from private.notification_intents previous
                where previous.fight_id = fight.id and previous.user_id = member.user_id
                    and previous.kind = 'fight_ended' and previous.copy_key = 'fight_ended_sync'
                    and previous.status = 'sent'
            )
        on conflict (idempotency_key) do nothing
    `;

    // A friend round waiting on someone who stopped syncing never finalizes, and the results push
    // waits for a person's last round. Once the month is over and the last of their rounds that
    // started in it ended a day ago, anyone with a finished round from it gets it. A weekly round
    // can end a week after the month, so the window counts from the month's end.
    await database`
        insert into private.notification_intents (
            idempotency_key, user_id, fight_id, kind, slot,
            not_before, expires_at, route, copy_key
        )
        select distinct on (member.user_id, month.key)
            member.user_id || ':friends_results:' || month.key,
            member.user_id, fight.id, 'friends_results', 'final',
            ${at}::timestamptz, ${at}::timestamptz + interval '24 hours',
            '/fights/' || fight.id || '?friends=1', 'friends_results'
        from public.fights fight
        cross join lateral (
            select to_char(fight.starts_at at time zone fight.time_zone, 'YYYY-MM') as key,
                (date_trunc('month', fight.starts_at at time zone fight.time_zone) + interval '1 month')
                    at time zone fight.time_zone as ends_at
        ) month
        join public.fight_members member on member.fight_id = fight.id and member.state = 'accepted'
        where fight.friends and fight.state = 'final'
            and month.ends_at <= ${at}::timestamptz
            and month.ends_at > ${at}::timestamptz - interval '9 days'
            and not exists (
                select 1 from public.fights round
                join public.fight_members mine on mine.fight_id = round.id
                    and mine.user_id = member.user_id and mine.state = 'accepted'
                where round.friends and round.state <> 'cancelled'
                    and to_char(round.starts_at at time zone round.time_zone, 'YYYY-MM') = month.key
                    and round.ends_at > ${at}::timestamptz - interval '1 day'
            )
        order by member.user_id, month.key, fight.id
        on conflict (idempotency_key) do nothing
    `;

    const candidates = digestCandidateSchema.array().parse(await database`
        select user_id, digest_on::text
        from private.notification_intents
        where kind in ('feed_post', 'post_reaction') and status = 'pending'
            and digest_on is not null and not_before <= ${at}::timestamptz
            and expires_at > ${at}::timestamptz
        group by user_id, digest_on
        order by digest_on, user_id
        limit 50
    `);
    for (const candidate of candidates) {
        await database.begin(async (sql) => {
            const events = digestEventSchema.array().parse(await sql`
                select id, fight_id, route from private.notification_intents
                where user_id = ${candidate.user_id} and digest_on = ${candidate.digest_on}::date
                    and kind in ('feed_post', 'post_reaction') and status = 'pending'
                    and not_before <= ${at}::timestamptz and expires_at > ${at}::timestamptz
                order by created_at, id for update skip locked
            `);
            if (events.length === 0) return;
            const [digest] = await sql`
                insert into private.notification_intents (
                    idempotency_key, user_id, fight_id, kind, slot,
                    not_before, expires_at, route, copy_key, digest_on
                )
                select ${candidate.user_id + ':evening:' + candidate.digest_on},
                    ${candidate.user_id}, ${events[0].fight_id}, 'social_digest', 'daily',
                    min(not_before), max(expires_at), ${events[0].route}, 'social_digest', ${candidate.digest_on}::date
                from private.notification_intents where id in ${sql(events.map((event) => event.id))}
                on conflict (idempotency_key) do update set idempotency_key = excluded.idempotency_key
                returning id
            `;
            await sql`
                update private.notification_intents
                set digest_id = ${digest.id}, status = 'skipped', skip_reason = 'superseded', processed_at = ${at}::timestamptz
                where id in ${sql(events.map((event) => event.id))}
            `;
        });
    }
}
