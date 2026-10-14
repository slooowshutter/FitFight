import { sendUserAlert } from "@/lib/notifications/send-user-alert";
import { grantReferralFreeCharacters } from "@/lib/supabase/queries/free-characters-supabase-query";

/**
 * Pays the referrals that became owed: after a referral is recorded, after Apple Health steps arrive, and in the
 * 15-minute sweep for steps resolved later. Without a user id it pays every owed referral. Each referrer gets one push.
 */
export async function rewardReferrals(referredUserId: string | null) {
    for (const payout of await grantReferralFreeCharacters(referredUserId)) {
        if (!payout.notify) continue;
        // NOTE: The grant is already saved and is never paid again, so one failed push must not stop the others.
        try {
            await sendUserAlert(payout.referrer_id, (french) => {
                const friend = payout.friend_handle ?? (french ? "Ton ami" : "Your friend");
                return french
                    ? { title: `${friend} a rejoint FitFight`, body: "Tu as un personnage gratuit." }
                    : { title: `${friend} joined FitFight`, body: "You have a free character." };
            }, { route: "/characters" });
        } catch (error) {
            console.error("fitfight_referral_push_failed", error instanceof Error ? error.name : "unknown");
        }
    }
}
