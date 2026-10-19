import type {
    AlertDefinition,
    AlertFacts,
    AlertLanguage,
    InAppAlert,
} from "@/lib/types/alerts/in-app-alert";

/**
 * Every in-app alert, highest priority first. The app shows the first matching alert the person has not
 * tapped or closed, then the next one, up to three per open. Never reuse or rename an id.
 * How to add one: docs/backend.md, "In-app alerts".
 */
export const inAppAlerts: AlertDefinition[] = [
    {
        id: "choose-your-companion",
        // choose_companion opens the picker from 1.3.0; 1.2.1 (234) would only close the alert. Profile photos no longer show, so this covers old photo users too.
        who: (facts) => versionAtLeast(facts.appVersion, "1.3.0") && !facts.companionPicture,
        title: { en: "Choose your companion", fr: "Choisissez votre compagnon" },
        body: {
            en: "Your companion is your picture in fights, on Feed and on your profile. Choose one so your friends see more than your initials.",
            fr: "Votre compagnon est votre image dans les défis, le Fil et votre profil. Choisissez-en un pour que vos amis voient plus que vos initiales.",
        },
        image: "/landing/companion-capybara-3.webp",
        buttons: [
            { title: { en: "Choose", fr: "Choisir" }, action: "choose_companion" },
            { title: { en: "Not now", fr: "Pas maintenant" }, action: "dismiss" },
        ],
    },
    {
        id: "start-first-fight",
        who: (facts) => facts.daysSinceSignup >= 3 && facts.fights === 0,
        title: { en: "Start your first fight", fr: "Lancez votre premier défi" },
        body: {
            en: "Add a friend by username, pick 3 days to a month, and see who walks more. You can also set what the loser has to do.",
            fr: "Ajoutez un ami avec son nom d’utilisateur, choisissez de 3 jours à un mois, et voyez qui marche le plus. Vous pouvez aussi choisir le gage du perdant.",
        },
        buttons: [
            { title: { en: "New fight", fr: "Nouveau défi" }, action: "new_fight" },
            { title: { en: "Not now", fr: "Pas maintenant" }, action: "dismiss" },
        ],
    },
    {
        id: "make-your-character",
        who: (facts) => facts.daysSinceSignup >= 1 && facts.customCharacters === 0,
        title: { en: "Make your own character", fr: "Créez votre propre personnage" },
        body: {
            en: "Describe anyone: a friend, your dog, yourself. Pick one of three portraits and make it your companion.",
            fr: "Décrivez qui vous voulez : un ami, votre chien, vous-même. Choisissez un des trois portraits et faites-en votre compagnon.",
        },
        image: "/landing/companion-alpaca-1.webp",
        buttons: [
            { title: { en: "Make mine", fr: "Créer le mien" }, action: "open_character" },
            { title: { en: "Not now", fr: "Pas maintenant" }, action: "dismiss" },
        ],
    },
];

/** Compares marketing versions number by number, so 1.10.0 comes after 1.9.0. */
export function versionAtLeast(version: string, minimum: string): boolean {
    return version.localeCompare(minimum, "en", { numeric: true }) >= 0;
}

export function alertsFor(
    facts: AlertFacts,
    language: AlertLanguage,
    origin: string,
    alerts: AlertDefinition[] = inAppAlerts,
): InAppAlert[] {
    return alerts
        .filter(
            (alert) =>
                !facts.answered.has(alert.id) &&
                // An update button needs Apple's installable build to link to.
                (facts.latestRelease !== null ||
                    alert.buttons.every((button) => button.action !== "update")) &&
                alert.who(facts),
        )
        .slice(0, 3)
        .map((alert) => ({
            id: alert.id,
            title: alert.title[language],
            body: alert.body[language],
            image_url: alert.image ? new URL(alert.image, origin).toString() : null,
            buttons: alert.buttons.map((button, index) => ({
                title: button.title[language],
                action: button.action,
                url: button.action === "update" ? (facts.latestRelease?.updateUrl ?? null) : null,
                primary: index === 0,
            })),
        }));
}
