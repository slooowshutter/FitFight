"use client";

import { useEffect, useId, useRef, useState } from "react";
import type { SiteLanguage } from "@/lib/types/marketing/site-language";

const TESTFLIGHT_URL = "https://testflight.apple.com/join/wcZKdwVZ";

const copy = {
    en: {
        installSteps: [
            [
                "First tap installs TestFlight.",
                "If you don't already have Apple's TestFlight app, this link installs TestFlight first. That is expected.",
            ],
            [
                "Tap the same link again to install FitFight.",
                "After TestFlight is on your iPhone, come back and open this same link a second time. That second tap is what adds FitFight.",
            ],
            [
                "You do not need a code.",
                "If TestFlight asks for a redemption code, you skipped the second tap. Close that screen and open this same link again.",
            ],
        ],
        getFitFight: "Get FitFight",
        betaOpens:
            "Try the FitFight beta through TestFlight. On iPhone, this page opens the TestFlight link after a few seconds.",
        storeOpens:
            "Download FitFight from the App Store. On iPhone, this page opens the App Store after a few seconds.",
        returnToMessage:
            "Once FitFight is installed, return to your friend's message and tap that original FitFight link again.",
        signIn: "Sign in to continue with your referral or challenge. You still choose whether to join.",
        openTestflight: "Open this TestFlight link",
        download: "Download on the App Store",
        alreadyInstalled:
            "Already have FitFight? Reopen the link from your friend's message to open the app.",
        betaEyebrow: "BETA ON TESTFLIGHT",
        installTitle: "How to install FitFight",
        installIntro:
            "Try the FitFight beta through TestFlight. Tap the same link twice to install it.",
        notNow: "Not now",
    },
    fr: {
        installSteps: [
            [
                "La première ouverture installe TestFlight.",
                "Si vous n’avez pas encore l’app TestFlight d’Apple, ce lien l’installe d’abord. C’est normal.",
            ],
            [
                "Ouvrez à nouveau le même lien pour installer FitFight.",
                "Une fois TestFlight sur votre iPhone, revenez ouvrir ce même lien une deuxième fois. C’est cette deuxième ouverture qui ajoute FitFight.",
            ],
            [
                "Aucun code n’est nécessaire.",
                "Si TestFlight demande un code d’échange, vous avez sauté la deuxième ouverture. Fermez cet écran et ouvrez à nouveau ce même lien.",
            ],
        ],
        getFitFight: "Obtenir FitFight",
        betaOpens:
            "Essayez la bêta de FitFight avec TestFlight. Sur iPhone, cette page ouvre le lien TestFlight après quelques secondes.",
        storeOpens:
            "Téléchargez FitFight sur l’App Store. Sur iPhone, cette page ouvre l’App Store après quelques secondes.",
        returnToMessage:
            "Une fois FitFight installé, revenez au message de votre ami et touchez à nouveau le lien FitFight d’origine.",
        signIn: "Connectez-vous pour continuer avec votre parrainage ou votre défi. Vous restez libre de rejoindre ou non.",
        openTestflight: "Ouvrir ce lien TestFlight",
        download: "Télécharger dans l’App Store",
        alreadyInstalled:
            "Vous avez déjà FitFight ? Rouvrez le lien reçu de votre ami pour ouvrir l’app.",
        betaEyebrow: "BÊTA SUR TESTFLIGHT",
        installTitle: "Comment installer FitFight",
        installIntro:
            "Essayez la bêta de FitFight avec TestFlight. Ouvrez le même lien deux fois pour l’installer.",
        notNow: "Pas maintenant",
    },
};

function TestflightInstallSteps({ language }: { language: SiteLanguage }) {
    return (
        <ol className="install-steps">
            {copy[language].installSteps.map(([title, detail]) => (
                <li key={title}>
                    <strong>{title}</strong> {detail}
                </li>
            ))}
        </ol>
    );
}

export function InviteDownload({
    isStaging,
    url,
    language,
}: {
    isStaging: boolean;
    url: string;
    language: SiteLanguage;
}) {
    const text = copy[language];

    useEffect(() => {
        const isIOS =
            /iPhone|iPad|iPod/.test(navigator.userAgent) ||
            (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
        if (!isIOS) return;
        const timer = window.setTimeout(() => {
            if (document.visibilityState === "visible") {
                window.location.assign(url);
            }
        }, 5000);
        return () => window.clearTimeout(timer);
    }, [url]);

    return (
        <section>
            <h2>{text.getFitFight}</h2>
            <p>{isStaging ? text.betaOpens : text.storeOpens}</p>
            {isStaging ? <TestflightInstallSteps language={language} /> : null}
            <p>
                <strong>{text.returnToMessage}</strong> {text.signIn}
            </p>
            <a
                className="primary-action invite-download"
                href={url}
                rel="noreferrer"
            >
                {isStaging ? text.openTestflight : text.download}
            </a>
            <p>{text.alreadyInstalled}</p>
        </section>
    );
}

export function TestflightInvite({
    label,
    kind,
    language,
}: {
    label: string;
    kind: "header" | "hero";
    language: SiteLanguage;
}) {
    const text = copy[language];
    const titleId = useId();
    const dialogRef = useRef<HTMLDialogElement>(null);
    const [open, setOpen] = useState(false);

    return (
        <>
            <button
                type="button"
                className={
                    kind === "header" ? "header-action" : "primary-action"
                }
                aria-haspopup="dialog"
                aria-expanded={open}
                onClick={() => {
                    dialogRef.current?.showModal();
                    setOpen(true);
                }}
            >
                {label}
            </button>
            <dialog
                ref={dialogRef}
                className="testflight-dialog"
                aria-labelledby={titleId}
                onClose={() => setOpen(false)}
                onClick={(event) => {
                    if (event.target === event.currentTarget) {
                        event.currentTarget.close();
                    }
                }}
            >
                <p className="eyebrow">{text.betaEyebrow}</p>
                <h2 id={titleId}>{text.installTitle}</h2>
                <p>{text.installIntro}</p>
                <TestflightInstallSteps language={language} />
                <a
                    className="primary-action"
                    href={TESTFLIGHT_URL}
                    target="_blank"
                    rel="noopener noreferrer"
                >
                    {text.openTestflight}
                </a>
                <button
                    type="button"
                    className="dialog-dismiss"
                    onClick={() => dialogRef.current?.close()}
                >
                    {text.notNow}
                </button>
            </dialog>
        </>
    );
}
