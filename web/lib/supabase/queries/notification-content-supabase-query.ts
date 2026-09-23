import type { Sql } from "postgres";
import { notificationAlert } from "@/lib/notifications/notification-copy";
import {
    notificationPostContextSchema,
    type NotificationContent,
    type NotificationDeliveryRow,
} from "@/lib/types/notifications/notification-delivery";
import { defaultNotificationPreferences } from "@/lib/types/notifications/notification-preferences";
import type { NotificationLocale } from "@/lib/types/notifications/device-installation";
import { signMediaUrl } from "./media-supabase-query";

/** Recheck content access at delivery so a delayed summary cannot reveal removed posts. */
export async function readNotificationContent(
    row: NotificationDeliveryRow,
    locale: NotificationLocale,
    database: Sql,
): Promise<NotificationContent | null> {
    const fr = locale === "fr";
    const prefs = { ...defaultNotificationPreferences, ...row.preferences };
    const social = ["social_digest", "post_comment", "comment_reply", "mention"].includes(row.kind);
    if (social) {
        const contexts = notificationPostContextSchema.array().parse(await database`
            with events as (
                select e.*,
                    coalesce(e.post_id, substring(e.route from '[?&]post=([a-f0-9-]+)')::uuid) as target_post,
                    coalesce(e.comment_id, substring(e.route from '[?&]comment=([a-f0-9-]+)')::uuid) as target_comment
                from private.notification_intents e
                where (e.id = ${row.id} and e.kind <> 'social_digest') or e.digest_id = ${row.id}
            )
            select e.kind, p.id as post_id, c.id as comment_id, e.fight_id,
                actor.handle as actor_handle, coalesce(c.body, p.body) as body,
                p.body as post_body, fight.name as fight_name, image.object_path as media_path
            from events e
            join public.fight_posts p on p.id = e.target_post
            join public.profiles author on author.id = p.author_id and author.deleted_at is null
            join public.fights fight on fight.id = e.fight_id and fight.state <> 'cancelled'
            left join public.fight_post_comments c on c.id = e.target_comment and c.post_id = p.id
            join public.profiles actor on actor.id = coalesce(e.actor_id, c.author_id,
                case when e.kind = 'post_reaction'
                    then substring(e.idempotency_key from '([a-f0-9-]+)$')::uuid else p.author_id end)
                and actor.deleted_at is null
            left join lateral (
                select media.object_path from public.fight_post_media attachment
                join public.media_objects media on media.id = attachment.media_id
                where attachment.post_id = p.id and media.status = 'ready' and media.kind = 'photo'
                order by attachment.sort, media.id limit 1
            ) image on true
            where (e.target_comment is null or c.id is not null)
                and (e.kind <> 'post_reaction' or exists (
                    select 1 from public.fight_post_reactions r
                    where r.post_id = p.id and r.user_id = actor.id
                ))
                and not exists (
                    select 1 from private.feed_blocks b
                    where (b.blocker_id = ${row.user_id} and b.blocked_id in (actor.id, author.id))
                        or (b.blocked_id = ${row.user_id} and b.blocker_id in (actor.id, author.id))
                )
                and (p.app_wide or exists (
                    select 1 from public.fight_members m
                    join public.fights accessible on accessible.id = m.fight_id
                    where m.user_id = ${row.user_id} and m.state in ('accepted', 'deferred')
                        and (
                            m.fight_id = p.fight_id
                            or exists (
                                select 1 from public.fight_post_channels channel
                                join public.fights original on original.id = channel.fight_id
                                where channel.post_id = p.id and (
                                    channel.fight_id = m.fight_id
                                    or (original.series_id is not null and original.series_id = accessible.series_id)
                                )
                            )
                            or exists (
                                select 1 from public.fights original
                                where original.id = p.fight_id and original.series_id is not null
                                    and original.series_id = accessible.series_id
                            )
                        )
                ))
            order by e.created_at, e.id
        `).filter((event) => event.kind === "feed_post" ? prefs.feed_post
            : event.kind === "post_reaction" ? prefs.post_reaction : true);
        if (contexts.length === 0) return null;
        const first = contexts[0];
        const postIds = new Set(contexts.map((event) => event.post_id));
        const onePost = postIds.size === 1;
        let title: string;
        let body: string;
        if (row.kind === "social_digest") {
            const reactions = contexts.filter((event) => event.kind === "post_reaction");
            const actors = [...new Set(reactions.map((event) => event.actor_handle))];
            const reactedPosts = new Set(reactions.map((event) => event.post_id)).size;
            const newPosts = new Set(contexts.filter((event) => event.kind === "feed_post").map((event) => event.post_id)).size;
            const parts: string[] = [];
            if (actors.length > 0) {
                const who = `@${actors[0]}` + (actors.length > 1
                    ? (fr ? ` et ${actors.length - 1} autre${actors.length > 2 ? "s" : ""}` : ` and ${actors.length - 1} other${actors.length > 2 ? "s" : ""}`) : "");
                parts.push(fr
                    ? `${who} ${actors.length > 1 ? "ont" : "a"} réagi à ${reactedPosts === 1 ? "ta publication" : `${reactedPosts} de tes publications`}.`
                    : `${who} reacted to ${reactedPosts === 1 ? "your post" : `${reactedPosts} of your posts`}.`);
            }
            if (newPosts > 0) parts.push(fr
                ? `${newPosts} nouvelle${newPosts > 1 ? "s" : ""} publication${newPosts > 1 ? "s" : ""} dans tes défis.`
                : `${newPosts} new post${newPosts > 1 ? "s" : ""} in your fights.`);
            title = onePost ? first.fight_name : (fr ? "Ton résumé du soir" : "Your evening summary");
            body = parts.join(" ");
            if (onePost && newPosts === 1 && actors.length === 0) {
                title = fr ? `@${first.actor_handle} a publié` : `@${first.actor_handle} posted`;
                body = first.fight_name;
            }
            if (onePost && first.post_body.trim()) body += ` « ${first.post_body.replace(/\s+/g, " ").trim().slice(0, 100)} »`;
        } else {
            const who = `@${first.actor_handle}`;
            title = row.kind === "comment_reply" ? (fr ? `${who} t’a répondu` : `${who} replied to you`)
                : row.kind === "post_comment" ? (fr ? `${who} a commenté ta publication` : `${who} commented on your post`)
                    : (fr ? `${who} t’a mentionné` : `${who} mentioned you`);
            const excerpt = first.body.replace(/\s+/g, " ").trim().slice(0, 140);
            body = first.fight_name + (excerpt ? ` · ${excerpt}` : "");
        }
        return {
            title, body,
            route: onePost ? `/fights/${first.fight_id}?post=${first.post_id}${first.comment_id ? `&comment=${first.comment_id}` : ""}`
                : `/fights/${first.fight_id}?activity=1`,
            threadId: onePost ? `post:${first.post_id}` : "evening-summary",
            imageUrl: onePost && first.media_path ? await signMediaUrl(first.media_path) : null,
        };
    }

    const deadline = new Intl.DateTimeFormat(fr ? "fr-FR" : "en-GB", {
        timeZone: row.time_zone, weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit",
    }).format(row.kind === "final_sync" ? row.sync_deadline : row.ends_at);
    let alert = notificationAlert(row.copy_key, locale);
    switch (row.kind) {
        case "fight_invite":
            alert = { title: row.fight_name, body: row.owner_handle
                ? (fr ? `@${row.owner_handle} t’a invité à ce défi.` : `@${row.owner_handle} invited you to this fight.`)
                : (fr ? "Tu as reçu une invitation à ce défi." : "You were invited to this fight.") };
            break;
        case "ending_24h":
        case "ending_week":
            alert = { title: row.fight_name, body: (row.kind === "ending_week"
                ? (fr ? "Encore une semaine." : "One week left.") : (fr ? "Encore un jour." : "One day left."))
                + (fr ? ` Fin : ${deadline}.` : ` Ends ${deadline}.`) };
            break;
        case "final_sync":
            alert = { title: row.fight_name, body: fr
                ? `Défi terminé. Ouvre FitFight avant le ${deadline} pour envoyer tes derniers pas.`
                : `Fight ended. Open FitFight before ${deadline} to submit your final steps.` };
            break;
        case "fight_ended":
            alert = { title: row.fight_name, body: fr ? "Défi terminé. Les résultats sont en attente des derniers pas." : "Fight ended. Results are waiting for the final steps." };
            break;
        case "fight_finalized":
            alert = { title: row.fight_name, body: fr ? "Les résultats sont confirmés. Découvre le classement final." : "The results are confirmed. See the final standings." };
            break;
        case "daily_status":
            alert = { title: row.fight_name, body: row.alert_body ?? alert.body };
            break;
    }
    return { ...alert, route: row.route, threadId: `fight:${row.fight_id}`, imageUrl: null };
}
