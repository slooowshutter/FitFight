"use client";

import { createClient } from "@supabase/supabase-js";
import { useState } from "react";
import { SignInButtons } from "@/components/sign-in-buttons";
import { InviteDownload } from "@/components/testflight-invite";
import { authProjects } from "@/lib/supabase/auth-projects";
import type { SiteLanguage } from "@/lib/types/marketing/site-language";
import { claimReferralResponseSchema } from "@/lib/types/referrals/referral";

const copy = {
    en: {
        title: "Get your free character",
        intro: "Create your FitFight account here first. When you connect Apple Health in the app, you and your friend each get a free character.",
        sameEmail:
            "Use the same email here and in the app. With Apple, choose Share My Email, not Hide My Email.",
        working: "Saving your invite…",
        failed: "Sign-in did not work. Try again.",
        skip: "Download without the free character",
        doneTitle: "Your invite is saved",
        doneNext: "Now download FitFight and sign in with the same email.",
        signedInAs: "You signed in as",
        oldTitle: "This account is not new",
        oldNext:
            "Invite characters are for accounts created in the last 7 days. Open FitFight and sign in with the same email.",
        locale: "en_US",
    },
    fr: {
        title: "Obtenez votre personnage gratuit",
        intro: "Créez d’abord votre compte FitFight ici. Quand vous connectez Apple Santé dans l’app, vous et votre ami recevez chacun un personnage gratuit.",
        sameEmail:
            "Utilisez la même adresse e-mail ici et dans l’app. Avec Apple, choisissez Partager mon adresse e-mail, pas Masquer mon adresse e-mail.",
        working: "Enregistrement de votre invitation…",
        failed: "La connexion n’a pas fonctionné. Réessayez.",
        skip: "Télécharger sans le personnage gratuit",
        doneTitle: "Votre invitation est enregistrée",
        doneNext:
            "Téléchargez maintenant FitFight et connectez-vous avec la même adresse e-mail.",
        signedInAs: "Vous êtes connecté avec",
        oldTitle: "Ce compte n’est pas nouveau",
        oldNext:
            "Les personnages d’invitation sont réservés aux comptes créés ces 7 derniers jours. Ouvrez FitFight et connectez-vous avec la même adresse e-mail.",
        locale: "fr_FR",
    },
};

/** The friend signs in here before installing, so the referral is saved on the server and survives the App Store. */
export function ReferralSignIn({
    code,
    language,
    download,
}: {
    code: string;
    language: SiteLanguage;
    download: { isStaging: boolean; url: string };
}) {
    const text = copy[language];
    const projectRef = download.isStaging ? "zstzbfocunthczzubggz" : "pvqntpteehdvhqyctwum";
    const [supabase] = useState(() =>
        createClient(authProjects[projectRef].url, authProjects[projectRef].publishableKey, {
            auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
        }),
    );
    const [step, setStep] = useState<"sign_in" | "working" | "done" | "not_new" | "skipped">("sign_in");
    const [failed, setFailed] = useState(false);
    const [email, setEmail] = useState<string | null>(null);

    if (step === "done" || step === "not_new" || step === "skipped") {
        return (
            <>
                {step === "skipped" ? null : (
                    <section>
                        <h2>{step === "done" ? text.doneTitle : text.oldTitle}</h2>
                        <p>
                            <strong>{step === "done" ? text.doneNext : text.oldNext}</strong>
                        </p>
                        {email ? (
                            <p>
                                {text.signedInAs} <strong>{email}</strong>.
                            </p>
                        ) : null}
                    </section>
                )}
                <InviteDownload {...download} language={language} signedIn={step !== "skipped"} />
            </>
        );
    }

    return (
        <section>
            <h2>{text.title}</h2>
            <p>{text.intro}</p>
            <p>
                <strong>{text.sameEmail}</strong>
            </p>
            <SignInButtons
                supabase={supabase}
                projectURL={authProjects[projectRef].url}
                locale={text.locale}
                hidden={step === "working"}
                className="referral-sign-in"
                onStart={() => {
                    setStep("working");
                    setFailed(false);
                }}
                onSignedIn={async (session) => {
                    const response = await fetch("/api/v1/referrals", {
                        method: "POST",
                        headers: {
                            authorization: `Bearer ${session.access_token}`,
                            "content-type": "application/json",
                        },
                        body: JSON.stringify({ code }),
                    });
                    if (!response.ok) throw new Error("referral_failed");
                    const claim = claimReferralResponseSchema.parse(await response.json());
                    setEmail(session.user.email ?? null);
                    setStep(claim.account_not_new ? "not_new" : "done");
                }}
                onFailed={() => {
                    setFailed(true);
                    setStep("sign_in");
                }}
            />
            {step === "working" ? <p>{text.working}</p> : null}
            {failed ? <p role="alert">{text.failed}</p> : null}
            <button type="button" className="dialog-dismiss referral-skip" onClick={() => setStep("skipped")}>
                {text.skip}
            </button>
        </section>
    );
}
