import { Badge } from "@/components/ui/badge";
import type { WebFight } from "@/lib/types/fights/web-fight";

export function FightTimeText({ fight }: { fight: WebFight }) {
    const daysLeft = Math.ceil(
        (new Date(fight.fight.ends_at).getTime() - Date.now()) / 86_400_000,
    );
    const ends = new Date(fight.fight.ends_at).toLocaleString(undefined, {
        weekday: "short",
        day: "numeric",
        month: "short",
        hour: "2-digit",
        minute: "2-digit",
    });
    return fight.status === "finished"
        ? `${fight.fight.state === "cancelled" ? "Cancelled" : "Ended"} ${ends}`
        : fight.status === "pending"
          ? "Waiting for final steps"
          : new Date(fight.fight.starts_at) > new Date()
            ? `Starts ${new Date(fight.fight.starts_at).toLocaleString(undefined, { weekday: "short", day: "numeric", month: "short" })}`
            : `${daysLeft} ${daysLeft === 1 ? "day" : "days"} left · ends ${ends}`;
}

export function FightResultBadge({ fight }: { fight: WebFight }) {
    const you = fight.standings.find((standing) => standing.you);
    const leader = fight.standings[0];
    if (fight.status === "invited") {
        return <Badge variant="secondary">Invited</Badge>;
    }
    if (fight.fight.state === "cancelled" || !you?.playing || !leader?.steps) {
        return null;
    }
    return leader === you ? (
        <Badge>{fight.status === "finished" ? "Won" : "You lead"}</Badge>
    ) : (
        <Badge variant="destructive">
            {fight.status === "finished"
                ? "Lost"
                : `${(leader.steps - you.steps).toLocaleString()} behind`}
        </Badge>
    );
}
