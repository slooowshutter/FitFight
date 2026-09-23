import type { NotificationLocale } from "@/lib/types/notifications/device-installation";

const socialKinds = [
    "feed_post",
    "post_comment",
    "comment_reply",
    "post_reaction",
] as const;

function actorLabel(name: string, locale: NotificationLocale): string {
    const cleaned = name.replace(/\s+/g, " ").trim().slice(0, 40);
    if (cleaned.length > 0) return cleaned;
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
