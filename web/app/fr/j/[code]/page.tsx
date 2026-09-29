import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { InviteDownload } from "@/components/testflight-invite";
import { appDownload } from "@/lib/releases/app-download";
import { isJoinCode, normalizeJoinCode } from "@/lib/domain/fights/join-code";

export const metadata: Metadata = {
    title: "Rejoindre un défi | FitFight",
    description:
        "Ouvrez ce lien d’invitation dans FitFight pour rejoindre le défi, même s’il est privé.",
    robots: { index: false, follow: false },
};

export default async function FrenchJoinPage({
    params,
}: {
    params: Promise<{ code: string }>;
}) {
    const { code } = await params;
    const display = normalizeJoinCode(code);
    if (!isJoinCode(display)) notFound();

    return (
        <main className="legal-page" lang="fr">
            <header className="legal-header">
                <Link
                    className="brand"
                    href="/fr"
                    aria-label="Accueil FitFight"
                >
                    <span className="brand-mark">FF</span>
                    <span>FitFight</span>
                </Link>
            </header>
            <article className="legal-content">
                <p className="eyebrow">REJOINDRE UN DÉFI</p>
                <h1>Ouvrez ce défi dans FitFight</h1>
                <p className="legal-intro">
                    Code <strong>{display}</strong>. Ouvrez ce lien d’invitation
                    dans FitFight pour rejoindre le défi, même s’il est privé.
                    Les scores restent dans l’app.
                </p>
                <InviteDownload {...appDownload()} language="fr" />
            </article>
            <footer className="legal-footer">
                <span>© 2026 FitFight</span>
                <a href={`/j/${display}?lang=en`} hrefLang="en" lang="en">
                    English
                </a>
            </footer>
        </main>
    );
}
