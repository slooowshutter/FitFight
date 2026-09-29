import type { Metadata } from "next";
import { TestflightInvite } from "@/components/testflight-invite";
import { TotalStepsCount } from "@/components/total-steps-count";
import { appDownload } from "@/lib/releases/app-download";
import { readCachedTotalSteps } from "@/lib/supabase/queries/total-steps-supabase-query";

import "../total-steps.css";

export const revalidate = 3600;

export const metadata: Metadata = {
    title: "FitFight : Défiez vos amis. Bougez pour gagner",
    description:
        "Le compteur de vos défis de pas. Connectez Santé d’Apple, lancez un défi privé en groupe et découvrez qui fait le plus de pas.",
};

export default async function FrenchHomePage() {
    const { isStaging, url } = appDownload();
    const { totalSteps } = await readCachedTotalSteps();

    return (
        <main lang="fr">
            <header className="site-header">
                <a className="brand" href="#top" aria-label="Accueil FitFight">
                    <span className="brand-mark">FF</span>
                    <span>FitFight</span>
                </a>
                {isStaging ? (
                    <TestflightInvite
                        label="Obtenir l’app"
                        kind="header"
                        language="fr"
                    />
                ) : (
                    <a className="header-action" href={url}>
                        Télécharger dans l’App Store
                    </a>
                )}
            </header>

            <section className="hero" id="top">
                <div className="hero-copy">
                    <p className="eyebrow">LE COMPTEUR DE VOS DÉFIS DE PAS</p>
                    <h1>
                        Bougez plus grâce aux défis
                        <br />
                        <span>entre amis.</span>
                    </h1>
                    <p className="lede">
                        Connectez Santé d’Apple, lancez un défi privé en groupe
                        et découvrez qui fait le plus de pas.
                    </p>
                    <div className="hero-actions">
                        {isStaging ? (
                            <TestflightInvite
                                label="Obtenir l’app"
                                kind="hero"
                                language="fr"
                            />
                        ) : (
                            <a className="primary-action" href={url}>
                                Télécharger dans l’App Store
                            </a>
                        )}
                        <a className="text-action" href="#how-it-works">
                            Voir comment ça marche{" "}
                            <span aria-hidden="true">↓</span>
                        </a>
                    </div>
                    <p className="platform-note">
                        {isStaging
                            ? "iPhone · Ouvrez le lien TestFlight deux fois · Santé d’Apple"
                            : "iPhone · Santé d’Apple"}
                    </p>
                </div>

                <div
                    className="fight-stage"
                    aria-label="Exemple de classement FitFight"
                >
                    <div className="orbit orbit-one" />
                    <div className="orbit orbit-two" />
                    <article className="fight-card">
                        <div className="card-topline">
                            <span className="status">
                                <span className="live-dot" /> DÉFI EN COURS
                            </span>
                            <span>Encore 2 j</span>
                        </div>
                        <div className="fight-title-row">
                            <div>
                                <p className="card-label">TOTAL DES PAS</p>
                                <h2>Défi de la semaine</h2>
                            </div>
                            <div className="rank">
                                <strong>#1</strong>
                                <span>SUR 2</span>
                            </div>
                        </div>

                        <div className="competitors">
                            <div className="competitor winner">
                                <div className="person">
                                    <span className="avatar">V</span>
                                    <div>
                                        <strong>Vous</strong>
                                        <small>8 420 pas</small>
                                    </div>
                                </div>
                                <div className="bar">
                                    <span />
                                </div>
                                <strong className="score">8,4 k</strong>
                            </div>
                            <div className="competitor behind">
                                <div className="person">
                                    <span className="avatar">L</span>
                                    <div>
                                        <strong>Leo</strong>
                                        <small>7 180 pas</small>
                                    </div>
                                </div>
                                <div className="bar">
                                    <span />
                                </div>
                                <strong className="score">7,1 k</strong>
                            </div>
                        </div>

                        <div className="card-footer">
                            <span>Continuez à bouger</span>
                            <strong>+1 240 d’avance</strong>
                        </div>
                    </article>
                    <div className="step-badge">
                        <svg aria-hidden="true" viewBox="0 0 24 24">
                            <path d="M8.1 3.4c1.5-.5 2.8.3 3.2 1.7.5 1.5-.2 3-1.7 3.5-1.5.5-2.8-.3-3.3-1.8-.4-1.4.3-2.9 1.8-3.4Zm6 6.7c1.8-.6 3.5.4 4.1 2.3.6 1.9-.3 3.8-2.1 4.4-1.8.6-3.5-.4-4.1-2.3-.6-1.9.3-3.8 2.1-4.4ZM5.2 10.5c1.2-.4 2.3.3 2.7 1.5.4 1.3-.2 2.5-1.4 2.9-1.2.4-2.3-.3-2.7-1.5-.4-1.2.2-2.5 1.4-2.9Zm4.2 5.1c1.5-.5 2.9.3 3.4 1.8.5 1.6-.2 3.1-1.7 3.6-1.5.5-2.9-.3-3.4-1.8-.5-1.5.2-3.1 1.7-3.6Z" />
                        </svg>
                    </div>
                </div>
            </section>

            <section
                className="total-steps"
                aria-label={`${totalSteps.toLocaleString("fr-FR")} pas enregistrés depuis que chacun a rejoint FitFight`}
            >
                <p className="eyebrow">PAS ENREGISTRÉS</p>
                <p className="total-steps-value" aria-hidden="true">
                    <TotalStepsCount totalSteps={totalSteps} language="fr" />
                </p>
                <p className="total-steps-caption">
                    depuis que chacun a rejoint FitFight
                </p>
            </section>

            <section className="how" id="how-it-works">
                <p className="eyebrow">COMMENT ÇA MARCHE</p>
                <h2>
                    Trois <span>étapes</span> pour se lancer. Un seul{" "}
                    <span>gagnant</span> à l’arrivée.
                </h2>
                <div className="steps">
                    <article>
                        <span>01</span>
                        <h3>Ajoutez vos amis</h3>
                        <p>
                            Recherchez-les par nom d’utilisateur et invitez-les
                            à un défi.
                        </p>
                    </article>
                    <article>
                        <span>02</span>
                        <h3>Bougez pour gagner</h3>
                        <p>
                            Santé d’Apple comptabilise vos pas en toute sécurité
                            pendant que vous vivez votre journée.
                        </p>
                    </article>
                    <article>
                        <span>03</span>
                        <h3>Décrochez la victoire</h3>
                        <p>
                            Suivez le classement, réduisez l’écart et terminez
                            en tête.
                        </p>
                    </article>
                </div>
            </section>

            <footer>
                <a className="brand" href="#top">
                    <span className="brand-mark">FF</span>
                    <span>FitFight</span>
                </a>
                <p>Défiez vos amis. Bougez pour gagner.</p>
                <span>
                    © 2026 FitFight ·{" "}
                    <a
                        className="language-link"
                        href="/?lang=en"
                        hrefLang="en"
                        lang="en"
                    >
                        English
                    </a>
                </span>
            </footer>
        </main>
    );
}
