import type { Sql } from "postgres";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    alertFactsRowSchema,
    type AlertFacts,
    type AlertResponseRequest,
} from "@/lib/types/alerts/in-app-alert";

/** The database facts alert rules read. The route adds the app version and Apple's latest release. */
export async function readAlertFacts(
    userId: string,
    database: Sql = createDatabaseClient(),
): Promise<Omit<AlertFacts, "appVersion" | "latestRelease">> {
    // NOTE: the fight filter is the admin dashboard's "real fights" rule: the app-wide (PGG7),
    // suggested, founder, and monthly friend fights are made for people, so they do not count.
    const [row] = await database`
        select
            (current_date - (p.created_at at time zone 'UTC')::date) as days_since_signup,
            (select count(*) from public.fight_members as m
                join public.fights as f on f.id = m.fight_id
                left join public.fight_series as series on series.id = f.series_id
                where m.user_id = p.user_id and m.state = 'accepted' and f.host_id is null and not f.friends
                    and coalesce(series.join_code, '') <> 'PGG7' and not coalesce(series.suggested, false)
            ) as fights,
            (select count(*) from private.custom_character_purchases as purchase
                join private.special_accounts as account on account.id = purchase.account_id
                where account.user_id = p.user_id and purchase.revoked_at is null
            ) as custom_characters,
            (p.companion_id is not null and (p.companion_id <> 'custom' or p.companion_image_url is not null))
                as companion_picture,
            (select count(*) from private.custom_character_purchases as purchase
                join private.special_accounts as account on account.id = purchase.account_id
                where account.user_id = p.user_id and purchase.revoked_at is null and purchase.free_claim_key is null
            ) + (select count(*) from private.special_purchases as purchase
                join private.special_accounts as account on account.id = purchase.account_id
                where account.user_id = p.user_id and purchase.revoked_at is null
            ) as purchases,
            (select count(*) from private.profile_friendships as friendship
                where friendship.state = 'accepted' and p.user_id in (friendship.user_low, friendship.user_high)
            ) as friends,
            (select coalesce(sum(latest.value), 0) from (
                select distinct on (metric.day) metric.value
                from private.activity_metrics as metric
                join public.data_sources as source on source.id = metric.source_id
                where metric.user_id = p.user_id and metric.scope = 'day' and metric.metric = 'steps'
                    and source.provider = 'apple_health'
                    and metric.day >= current_date - 7 and metric.day < current_date
                order by metric.day, metric.updated_at desc
            ) as latest) as steps_last_7_days,
            array(select distinct response.alert_id from private.alert_responses as response
                where response.user_id = p.user_id and response.response in ('tapped', 'dismissed')
            ) as answered
        from public.profiles as p
        where p.user_id = ${userId}
    `;
    const facts = alertFactsRowSchema.parse(row);
    return {
        daysSinceSignup: facts.days_since_signup,
        fights: facts.fights,
        customCharacters: facts.custom_characters,
        companionPicture: facts.companion_picture,
        purchases: facts.purchases,
        friends: facts.friends,
        stepsLast7Days: facts.steps_last_7_days,
        answered: new Set(facts.answered),
    };
}

export async function recordAlertResponse(
    userId: string,
    alertId: string,
    input: AlertResponseRequest,
    appVersion: string | null,
    appBuild: string | null,
    database: Sql = createDatabaseClient(),
): Promise<void> {
    await database`
        insert into private.alert_responses (user_id, alert_id, response, action, app_version, app_build)
        values (${userId}, ${alertId}, ${input.response}, ${input.action ?? null}, ${appVersion}, ${appBuild})
    `;
}
