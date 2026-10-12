import { LandingPage } from "@/components/landing/landing-page";
import { appDownload } from "@/lib/releases/app-download";
import {
    readCachedJoiningLift,
    readCachedTotalSteps,
} from "@/lib/supabase/queries/total-steps-supabase-query";

import "./landing.css";

export const revalidate = 3600;

export default async function HomePage() {
    const [{ totalSteps }, { joiningLift }] = await Promise.all([
        readCachedTotalSteps(),
        readCachedJoiningLift(),
    ]);

    return (
        <LandingPage
            language="en"
            download={appDownload()}
            totalSteps={totalSteps}
            joiningLift={joiningLift}
        />
    );
}
