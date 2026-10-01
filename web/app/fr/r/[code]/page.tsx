import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { InviteDownload } from "@/components/testflight-invite";
import { appDownload } from "@/lib/releases/app-download";
import { referralCodeSchema } from "@/lib/types/referrals/referral";

export const metadata: Metadata = {
    title: "Un ami vous invite | FitFight",
    description:
        "Rejoignez votre ami sur FitFight et lancez-vous des défis pour marcher plus.",
    robots: { index: false, follow: false },
};

export default async function FrenchReferralPage({
    params,
}: {
    params: Promise<{ code: string }>;
}) {
    const parsed = referralCodeSchema.safeParse((await params).code);
    if (!parsed.success) notFound();

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
                <p className="eyebrow">INVITATION D’UN AMI</p>
                <h1>Marchez plus. Ensemble.</h1>
                <p className="legal-intro">
                    Un ami vous invite sur FitFight. Lancez-vous des défis pour
                    marcher plus, comparez vos pas et faites compter chaque
                    journée.
                </p>
                <InviteDownload {...appDownload()} language="fr" />
            </article>
            <footer className="legal-footer">
                <span>© 2026 FitFight</span>
                <a href={`/r/${parsed.data}?lang=en`} hrefLang="en" lang="en">
                    English
                </a>
            </footer>
        </main>
    );
}
