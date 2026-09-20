import { notificationAlert } from "./notification-copy";

export function resolveNotificationAlert(input: {
    kind: string;
    copyKey: string;
    alertBody: string | null;
    locale: "en" | "fr" | null | undefined;
}): { title: string; body: string } {
    if (input.alertBody) return { title: "FitFight", body: input.alertBody };
    return notificationAlert(input.copyKey, input.locale);
}
