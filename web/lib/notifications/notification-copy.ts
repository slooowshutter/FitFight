import { notificationCopyKeySchema } from "@/lib/types/notifications/notification-intent";
import type { NotificationLocale } from "@/lib/types/notifications/device-installation";

const copy: Record<
    ReturnType<typeof notificationCopyKeySchema.parse>,
    Record<NotificationLocale, { title: string; body: string }>
> = {
    ending_24h: {
        en: { title: "One day left", body: "Your fight ends tomorrow." },
        fr: { title: "Encore un jour", body: "Ton défi se termine demain." },
    },
    ending_week: {
        en: { title: "One week left", body: "Your month-long fight ends in one week." },
        fr: { title: "Encore une semaine", body: "Ton défi d’un mois se termine dans une semaine." },
    },
    final_sync: {
        en: { title: "Submit your final steps", body: "Your fight has ended. Open FitFight to submit your final steps." },
        fr: { title: "Envoie tes derniers pas", body: "Ton défi est terminé. Ouvre FitFight pour envoyer tes derniers pas." },
    },
    social_digest: {
        en: { title: "Your evening summary", body: "There is new activity in your fights." },
        fr: { title: "Ton résumé du soir", body: "Il y a du nouveau dans tes défis." },
    },
    fight_ended_everyone: {
        en: { title: "FitFight", body: "A fight ended. Open FitFight." },
        fr: {
            title: "FitFight",
            body: "Un défi est terminé. Ouvrez FitFight.",
        },
    },
    fight_ended_sync: {
        en: {
            title: "FitFight",
            body: "A fight ended. Open FitFight to sync your steps.",
        },
        fr: {
            title: "FitFight",
            body: "Un défi est terminé. Ouvrez FitFight pour synchroniser vos pas.",
        },
    },
    grace_12h: {
        en: {
            title: "FitFight",
            body: "12 hours left. Open FitFight or you lose.",
        },
        fr: {
            title: "FitFight",
            body: "12 heures restantes. Ouvrez FitFight ou vous perdez.",
        },
    },
    grace_6h: {
        en: {
            title: "FitFight",
            body: "6 hours left. Open FitFight or you lose.",
        },
        fr: {
            title: "FitFight",
            body: "6 heures restantes. Ouvrez FitFight ou vous perdez.",
        },
    },
    grace_1h: {
        en: {
            title: "FitFight",
            body: "Last hour. Open FitFight or you lose.",
        },
        fr: {
            title: "FitFight",
            body: "Dernière heure. Ouvrez FitFight ou vous perdez.",
        },
    },
    fight_finalized: {
        en: { title: "FitFight", body: "The result is in. Open FitFight." },
        fr: {
            title: "FitFight",
            body: "Le résultat est tombé. Ouvrez FitFight.",
        },
    },
    daily_status: {
        en: {
            title: "FitFight",
            body: "Your fight has an update. Open FitFight.",
        },
        fr: {
            title: "FitFight",
            body: "Votre défi a une mise à jour. Ouvrez FitFight.",
        },
    },
    feed_post: {
        en: { title: "FitFight", body: "Someone posted in the feed." },
        fr: { title: "FitFight", body: "Quelqu’un a publié dans le fil." },
    },
    post_comment: {
        en: { title: "FitFight", body: "Someone commented on your post." },
        fr: { title: "FitFight", body: "Quelqu’un a commenté ta publication." },
    },
    comment_reply: {
        en: { title: "FitFight", body: "Someone replied to your comment." },
        fr: {
            title: "FitFight",
            body: "Quelqu’un a répondu à ton commentaire.",
        },
    },
    post_reaction: {
        en: { title: "FitFight", body: "Someone reacted to your post." },
        fr: { title: "FitFight", body: "Quelqu’un a réagi à ta publication." },
    },
    fight_invite: {
        en: {
            title: "FitFight",
            body: "You were invited to a fight. Open FitFight.",
        },
        fr: {
            title: "FitFight",
            body: "Tu as été invité à un défi. Ouvre FitFight.",
        },
    },
    mention_post: {
        en: { title: "FitFight", body: "Someone tagged you in a post." },
        fr: {
            title: "FitFight",
            body: "Quelqu’un t’a mentionné dans une publication.",
        },
    },
    mention_comment: {
        en: { title: "FitFight", body: "Someone tagged you in a comment." },
        fr: {
            title: "FitFight",
            body: "Quelqu’un t’a mentionné dans un commentaire.",
        },
    },
};

const socialKinds = [
    "feed_post",
    "post_comment",
    "comment_reply",
    "post_reaction",
] as const;

function actorLabel(name: string, locale: NotificationLocale): string {
    const cleaned = name.replace(/\s+/g, " ").trim().slice(0, 40);
    if (cleaned.length > 0) return `@${cleaned.replace(/^@/, "")}`;
    return locale === "fr" ? "Quelqu’un" : "Someone";
}

export function socialNotificationAlert(
    kind: (typeof socialKinds)[number],
    actorName: string,
    locale: NotificationLocale | null | undefined,
): { title: string; body: string } {
    const language: NotificationLocale = locale === "fr" ? "fr" : "en";
    const name = actorLabel(actorName, language);
    const bodies: Record<
        (typeof socialKinds)[number],
        Record<NotificationLocale, string>
    > = {
        feed_post: {
            en: `${name} posted in the feed.`,
            fr: `${name} a publié dans le fil.`,
        },
        post_comment: {
            en: `${name} commented on your post.`,
            fr: `${name} a commenté ta publication.`,
        },
        comment_reply: {
            en: `${name} replied to your comment.`,
            fr: `${name} a répondu à ton commentaire.`,
        },
        post_reaction: {
            en: `${name} reacted to your post.`,
            fr: `${name} a réagi à ta publication.`,
        },
    };
    return { title: "FitFight", body: bodies[kind][language] };
}

const mentionSurfaces = ["post", "comment"] as const;

export function mentionNotificationAlert(
    surface: (typeof mentionSurfaces)[number],
    actorName: string,
    locale: NotificationLocale | null | undefined,
): { title: string; body: string } {
    const language: NotificationLocale = locale === "fr" ? "fr" : "en";
    const name = actorLabel(actorName, language);
    switch (surface) {
        case "post":
            return {
                title: "FitFight",
                body:
                    language === "fr"
                        ? `${name} t’a mentionné dans une publication.`
                        : `${name} tagged you in a post.`,
            };
        case "comment":
            return {
                title: "FitFight",
                body:
                    language === "fr"
                        ? `${name} t’a mentionné dans un commentaire.`
                        : `${name} tagged you in a comment.`,
            };
        default: {
            const _exhaustive: never = surface;
            return _exhaustive;
        }
    }
}

export function inviteNotificationAlert(
    actorName: string,
    fightName: string,
    locale: NotificationLocale | null | undefined,
): { title: string; body: string } {
    const language: NotificationLocale = locale === "fr" ? "fr" : "en";
    const name = actorLabel(actorName, language);
    const fight = fightName.replace(/\s+/g, " ").trim().slice(0, 40);
    const labeled =
        fight.length > 0 ? fight : language === "fr" ? "un défi" : "a fight";
    return {
        title: "FitFight",
        body:
            language === "fr"
                ? `${name} t'a invité à ${labeled}.`
                : `${name} invited you to ${labeled}.`,
    };
}

export function notificationAlert(
    copyKey: string,
    locale: NotificationLocale | null | undefined,
): { title: string; body: string } {
    const key = notificationCopyKeySchema.parse(copyKey);
    const language: NotificationLocale = locale === "fr" ? "fr" : "en";
    return copy[key][language];
}
