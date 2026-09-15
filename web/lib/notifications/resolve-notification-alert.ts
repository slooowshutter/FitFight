import { notificationCopyKeySchema } from "@/lib/types/notifications/notification-intent";

const fallbackCopy = {
    en: {
        title: "FitFight",
        body: "Your fight has an update. Open FitFight.",
    },
    fr: {
        title: "FitFight",
        body: "Votre défi a une mise à jour. Ouvrez FitFight.",
    },
} as const;

const staticCopy: Record<
    ReturnType<typeof notificationCopyKeySchema.parse>,
    Record<"en" | "fr", { title: string; body: string }>
> = {
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
    daily_status: fallbackCopy,
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
};

export function resolveNotificationAlert(input: {
    kind: string;
    copyKey: string;
    alertBody: string | null;
    locale: "en" | "fr" | null | undefined;
}): { title: string; body: string } {
    const language = input.locale === "fr" ? "fr" : "en";
    if (input.alertBody) {
        return { title: "FitFight", body: input.alertBody };
    }
    const key = notificationCopyKeySchema.parse(input.copyKey);
    return staticCopy[key][language];
}
