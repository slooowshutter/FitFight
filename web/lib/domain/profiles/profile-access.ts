import type { ProfileAccess, ProfileRelationship, ProfileSettings } from "@/lib/types/profiles/shared-profile";

/** Profile audience never grants permission to a private Fight's other content. */
export function profileAccess(settings: ProfileSettings, relationship: ProfileRelationship): ProfileAccess {
    if (relationship.blocked) return { identity: false, record: false, activity: false, shared: false };
    if (relationship.owner) return { identity: true, record: true, activity: true, shared: true };
    const shared = settings.audience === "public" || relationship.friend || relationship.current_opponent;
    const activity = settings.activity_audience === "friends"
        ? relationship.friend
        : settings.activity_audience === "opponents"
            ? relationship.friend || relationship.current_opponent
            : settings.activity_audience === "public" && settings.audience === "public";
    return { identity: true, shared, record: shared && settings.competitive, activity: shared && activity };
}
