import { LandingPage } from "@/components/landing/landing-page";
import { appDownload } from "@/lib/releases/app-download";
import { readCachedTotalSteps } from "@/lib/supabase/queries/total-steps-supabase-query";

import "./landing.css";

export const revalidate = 3600;

export default async function HomePage() {
    const { totalSteps } = await readCachedTotalSteps();

    return (
        <LandingPage
            language="en"
            download={appDownload()}
            totalSteps={totalSteps}
        />
    );
}
