"use client";

import { createClient } from "@supabase/supabase-js";
import Script from "next/script";
import { useEffect, useRef, useState } from "react";
import { InviteDownload } from "@/components/testflight-invite";
import { googleOAuthClients } from "@/lib/google/google-clients";
import { authProjects } from "@/lib/supabase/auth-projects";
import type { AppleSignInSuccess } from "@/lib/types/auth/web-sign-in";
import type { SiteLanguage } from "@/lib/types/marketing/site-language";
import { claimReferralResponseSchema } from "@/lib/types/referrals/referral";

// NOTE: Marc creates this Services ID grouped with the app's App ID, so Apple gives the website and the app the same
// account. Its return URLs are both site roots.
const APPLE_SERVICES_ID = "com.fitfight.mvp.web";

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

/**
 * The friend signs in here before installing, so the referral is saved on the server and survives the App Store. Same
 * rule as the app: Google first joins an account that already uses its verified email.
 */
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
    const googleClientId = googleOAuthClients[`${projectRef}.supabase.co`].webClientID;
    const [supabase] = useState(() =>
        createClient(authProjects[projectRef].url, authProjects[projectRef].publishableKey, {
            auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
        }),
    );
    const [nonce, setNonce] = useState<{ raw: string; hashed: string } | null>(null);
    const [scripts, setScripts] = useState({ apple: false, google: false });
    const [step, setStep] = useState<"sign_in" | "working" | "done" | "not_new" | "skipped">("sign_in");
    const [failed, setFailed] = useState(false);
    const [email, setEmail] = useState<string | null>(null);
    const googleButton = useRef<HTMLDivElement>(null);
    const signInRef = useRef<(provider: "apple" | "google", token: string) => void>(() => {});

    // Both providers put the SHA-256 of the nonce in their ID token; Supabase checks it against the raw one.
    useEffect(() => {
        const raw = crypto.randomUUID();
        crypto.subtle.digest("SHA-256", new TextEncoder().encode(raw)).then((digest) =>
            setNonce({
                raw,
                hashed: [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join(""),
            }),
        );
    }, []);

    signInRef.current = async (provider, token) => {
        if (!nonce) return;
        setStep("working");
        setFailed(false);
        try {
            if (provider === "google") {
                const linked = await fetch("/api/v1/auth/google", {
                    method: "POST",
                    headers: { "content-type": "application/json" },
                    body: JSON.stringify({ id_token: token, nonce: nonce.raw }),
                });
                if (!linked.ok) throw new Error("google_link_failed");
            }
            const { data, error } = await supabase.auth.signInWithIdToken({ provider, token, nonce: nonce.raw });
            if (error) throw error;
            const response = await fetch("/api/v1/referrals", {
                method: "POST",
                headers: {
                    authorization: `Bearer ${data.session.access_token}`,
                    "content-type": "application/json",
                },
                body: JSON.stringify({ code }),
            });
            if (!response.ok) throw new Error("referral_failed");
            const claim = claimReferralResponseSchema.parse(await response.json());
            setEmail(data.user.email ?? null);
            setStep(claim.account_not_new ? "not_new" : "done");
        } catch {
            setFailed(true);
            setStep("sign_in");
        }
    };

    useEffect(() => {
        if (!nonce || !scripts.apple || !window.AppleID) return;
        window.AppleID.auth.init({
            clientId: APPLE_SERVICES_ID,
            scope: "name email",
            redirectURI: `${window.location.origin}/`,
            usePopup: true,
            nonce: nonce.hashed,
        });
        const succeeded = (event: Event) =>
            signInRef.current("apple", (event as CustomEvent<AppleSignInSuccess>).detail.authorization.id_token);
        const rejected = () => setFailed(true);
        document.addEventListener("AppleIDSignInOnSuccess", succeeded);
        document.addEventListener("AppleIDSignInOnFailure", rejected);
        return () => {
            document.removeEventListener("AppleIDSignInOnSuccess", succeeded);
            document.removeEventListener("AppleIDSignInOnFailure", rejected);
        };
    }, [nonce, scripts.apple]);

    useEffect(() => {
        if (!nonce || !scripts.google || !window.google || !googleButton.current) return;
        window.google.accounts.id.initialize({
            client_id: googleClientId,
            nonce: nonce.hashed,
            callback: ({ credential }) => signInRef.current("google", credential),
        });
        window.google.accounts.id.renderButton(googleButton.current, {
            theme: "outline",
            size: "large",
            text: "continue_with",
            shape: "rectangular",
            width: 300,
            locale: text.locale,
        });
    }, [nonce, scripts.google, googleClientId, text.locale]);

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
            <Script
                src={`https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/${text.locale}/appleid.auth.js`}
                onReady={() => setScripts((loaded) => ({ ...loaded, apple: true }))}
            />
            <Script
                src="https://accounts.google.com/gsi/client"
                onReady={() => setScripts((loaded) => ({ ...loaded, google: true }))}
            />
            <h2>{text.title}</h2>
            <p>{text.intro}</p>
            <p>
                <strong>{text.sameEmail}</strong>
            </p>
            <div className="referral-sign-in" aria-busy={step === "working"} hidden={step === "working"}>
                <div
                    id="appleid-signin"
                    data-color="white"
                    data-border="false"
                    data-type="continue"
                    data-width="300"
                    data-height="40"
                />
                <div ref={googleButton} />
            </div>
            {step === "working" ? <p>{text.working}</p> : null}
            {failed ? <p role="alert">{text.failed}</p> : null}
            <button type="button" className="dialog-dismiss referral-skip" onClick={() => setStep("skipped")}>
                {text.skip}
            </button>
        </section>
    );
}
