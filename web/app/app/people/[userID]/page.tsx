"use client";

import { useParams, useSearchParams } from "next/navigation";
import { ProfileView } from "@/components/web-app/profile-view";
import { profileViewRequestSchema } from "@/lib/types/profiles/shared-profile";

/** Someone's Profile. Links say where they came from with `?from=` (standings, feed...), which a profile view records. */
export default function PersonPage() {
    const { userID } = useParams<{ userID: string }>();
    const from = profileViewRequestSchema.shape.source.safeParse(
        useSearchParams().get("from"),
    );
    return (
        <ProfileView
            key={userID}
            userID={userID.toLowerCase()}
            source={from.success ? from.data : undefined}
        />
    );
}
