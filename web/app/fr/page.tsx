import type { Metadata } from "next";
import { LandingPage } from "@/components/landing/landing-page";
import { appDownload } from "@/lib/releases/app-download";
import { readCachedTotalSteps } from "@/lib/supabase/queries/total-steps-supabase-query";

import "../landing.css";

export const revalidate = 3600;

export const metadata: Metadata = {
    title: "FitFight : Défiez vos amis. Bougez pour gagner",
    description:
        "Le compteur de vos défis de pas. Connectez Santé d’Apple, lancez un défi privé en groupe et découvrez qui fait le plus de pas.",
};

export default async function FrenchHomePage() {
    const { totalSteps } = await readCachedTotalSteps();

    return (
        <LandingPage
            language="fr"
            download={appDownload()}
            totalSteps={totalSteps}
        />
    );
}
