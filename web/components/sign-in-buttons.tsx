"use client";

import type { Session, SupabaseClient } from "@supabase/supabase-js";
import Script from "next/script";
import { useEffect, useRef, useState } from "react";
import { googleOAuthClientsForProject } from "@/lib/google/google-clients";
import type { AppleSignInSuccess } from "@/lib/types/auth/web-sign-in";

// NOTE: Marc creates this Services ID grouped with the app's App ID, so Apple gives the website and the app the same
// account. Its return URLs are both site roots.
const APPLE_SERVICES_ID = "com.fitfight.mvp.web";

/**
 * Sign in with Apple and Google in the browser, into the same Supabase account the app uses. Same rule as the app:
 * Google first joins an account that already uses its verified email.
 */
export function SignInButtons({
    supabase,
    projectURL,
    locale,
    hidden,
    className,
    onStart,
    onSignedIn,
    onFailed,
}: {
    supabase: SupabaseClient;
    projectURL: string;
    locale: string;
    hidden: boolean;
    className: string;
    onStart: () => void;
    onSignedIn: (session: Session) => Promise<void>;
    onFailed: () => void;
}) {
    const googleClientId =
        googleOAuthClientsForProject(projectURL)?.webClientID;
    const [nonce, setNonce] = useState<{ raw: string; hashed: string } | null>(
        null,
    );
    const [scripts, setScripts] = useState({ apple: false, google: false });
    const googleButton = useRef<HTMLDivElement>(null);
    const signInRef = useRef<
        (provider: "apple" | "google", token: string) => void
    >(() => {});
    const failedRef = useRef(onFailed);
    failedRef.current = onFailed;

    // Both providers put the SHA-256 of the nonce in their ID token; Supabase checks it against the raw one.
    useEffect(() => {
        const raw = crypto.randomUUID();
        crypto.subtle
            .digest("SHA-256", new TextEncoder().encode(raw))
            .then((digest) =>
                setNonce({
                    raw,
                    hashed: [...new Uint8Array(digest)]
                        .map((byte) => byte.toString(16).padStart(2, "0"))
                        .join(""),
                }),
            );
    }, []);

    signInRef.current = async (provider, token) => {
        if (!nonce) return;
        onStart();
        try {
            if (provider === "google") {
                const linked = await fetch("/api/v1/auth/google", {
                    method: "POST",
                    headers: { "content-type": "application/json" },
                    body: JSON.stringify({ id_token: token, nonce: nonce.raw }),
                });
                if (!linked.ok) throw new Error("google_link_failed");
            }
            const { data, error } = await supabase.auth.signInWithIdToken({
                provider,
                token,
                nonce: nonce.raw,
            });
            if (error) throw error;
            await onSignedIn(data.session);
        } catch {
            failedRef.current();
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
            signInRef.current(
                "apple",
                (event as CustomEvent<AppleSignInSuccess>).detail.authorization
                    .id_token,
            );
        const rejected = () => failedRef.current();
        document.addEventListener("AppleIDSignInOnSuccess", succeeded);
        document.addEventListener("AppleIDSignInOnFailure", rejected);
        return () => {
            document.removeEventListener("AppleIDSignInOnSuccess", succeeded);
            document.removeEventListener("AppleIDSignInOnFailure", rejected);
        };
    }, [nonce, scripts.apple]);

    useEffect(() => {
        if (
            !nonce ||
            !scripts.google ||
            !window.google ||
            !googleButton.current ||
            !googleClientId
        )
            return;
        window.google.accounts.id.initialize({
            client_id: googleClientId,
            nonce: nonce.hashed,
            callback: ({ credential }) =>
                signInRef.current("google", credential),
        });
        window.google.accounts.id.renderButton(googleButton.current, {
            theme: "outline",
            size: "large",
            text: "continue_with",
            shape: "rectangular",
            width: 300,
            locale,
        });
    }, [nonce, scripts.google, googleClientId, locale]);

    return (
        <>
            <Script
                src={`https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/${locale}/appleid.auth.js`}
                onReady={() =>
                    setScripts((loaded) => ({ ...loaded, apple: true }))
                }
            />
            <Script
                src="https://accounts.google.com/gsi/client"
                onReady={() =>
                    setScripts((loaded) => ({ ...loaded, google: true }))
                }
            />
            <div className={className} aria-busy={hidden} hidden={hidden}>
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
        </>
    );
}
