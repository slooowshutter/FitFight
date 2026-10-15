import type { FightSnapshot } from "@/lib/types/fights/fight-snapshot";

/**
 * The web app's view of a Fights snapshot, bucketed the way the iPhone app's AppModel does: invited, live, pending
 * (ended, waiting for final steps) and finished. Standings put real players first by score, invitees last.
 */
export function webFights(
    snapshot: FightSnapshot,
    userId: string,
    now = new Date(),
) {
    return snapshot.fights.flatMap((fight) => {
        const members = snapshot.members.filter(
            (member) => member.fight_id === fight.id,
        );
        const mine = members.find((member) => member.user_id === userId);
        if (
            fight.state === "draft" ||
            mine?.state === "declined" ||
            mine?.state === "withdrawn"
        )
            return [];

        const ended = fight.state === "final" || fight.state === "cancelled";
        const status =
            mine?.state === "invited" && !ended
                ? "invited"
                : ended
                  ? "finished"
                  : fight.state === "awaiting_final_sync" ||
                      (fight.state === "live" && new Date(fight.ends_at) < now)
                    ? "pending"
                    : "live";

        const standings = members
            .filter(
                (member) =>
                    member.state === "accepted" ||
                    member.state === "invited" ||
                    member.state === "deferred",
            )
            .flatMap((member) => {
                const profile = snapshot.profiles.find(
                    (candidate) => candidate.user_id === member.user_id,
                );
                return profile
                    ? [
                          {
                              member,
                              profile,
                              you: member.user_id === userId,
                              playing: member.state === "accepted",
                              steps:
                                  member.final_value ??
                                  member.current_value ??
                                  0,
                          },
                      ]
                    : [];
            })
            .sort(
                (left, right) =>
                    Number(right.playing) - Number(left.playing) ||
                    right.steps - left.steps,
            );

        return [
            {
                fight,
                status,
                standings,
                series:
                    snapshot.series.find(
                        (series) => series.id === fight.series_id,
                    ) ?? null,
            },
        ];
    });
}
