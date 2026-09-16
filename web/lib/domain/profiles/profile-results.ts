import type { ClassifiedFightResult, FightRecordFact } from "@/lib/types/profiles/profile-results";
import type { ProfileRecord, RivalryRecord } from "@/lib/types/profiles/shared-profile";

/** Uses frozen results and participation evidence; rank alone never establishes a win. */
export function classifyFightResult(fight: FightRecordFact, userId: string): ClassifiedFightResult {
    const member = fight.members.find((item) => item.user_id === userId);
    const entrants = fight.members.filter((item) => item.entered_at !== null
        && Date.parse(item.entered_at) < Date.parse(fight.ends_at)
        && (item.departed_at === null || Date.parse(item.departed_at) > Date.parse(fight.starts_at)));
    const fieldSize = fight.summary?.field_size ?? entrants.length;
    const excluded = { counted: false, fieldSize, placement: member?.rank ?? null };
    if (!member) return { ...excluded, result: "not_entered" };
    if (fight.state === "cancelled") return { ...excluded, result: "cancelled" };
    if (fight.state !== "final") return { ...excluded, result: "ongoing" };
    if (member.departure === "removed") return { ...excluded, result: "removed" };
    if (!member.reliable || fight.outcome_rule !== "highest_total"
        || (fight.summary ? !fight.summary.verified : fight.members.some((item) => !item.reliable && !["invited", "declined", "deferred"].includes(item.state)))) {
        return { ...excluded, result: "unavailable" };
    }
    if (!entrants.includes(member)) return { ...excluded, result: "not_entered" };
    if (fieldSize < 2) return { ...excluded, result: "solo" };
    if (member.departure === "voluntary") return { ...excluded, counted: true, result: "withdrawn", placement: null };
    if (member.departure === "unknown" || member.finalized_at === null || member.complete === null || member.rank === null) {
        return { ...excluded, result: "unavailable" };
    }
    const finishers = entrants.filter((item) => item.departure === null);
    if (finishers.some((item) => item.finalized_at === null || item.complete === null || item.rank === null)) {
        return { ...excluded, result: "unavailable" };
    }
    const complete = finishers.filter((item) => item.complete);
    const completeCount = fight.summary?.complete_finishers ?? complete.length;
    const firstPlaceCount = fight.summary?.first_place_finishers ?? complete.filter((item) => item.rank === 1).length;
    const result = completeCount === 0
        ? "draw"
        : !member.complete
            ? "incomplete"
            : member.rank !== 1
                ? "loss"
                : firstPlaceCount === 1 ? "win" : "draw";
    return { ...excluded, counted: true, result };
}

export function profileRecord(fights: FightRecordFact[], userId: string): ProfileRecord {
    const record: ProfileRecord = {
        played: 0, wins: 0, win_rate: null, excluded: 0,
        categories: {
            public: { played: 0, wins: 0, win_rate: null },
            private: { played: 0, wins: 0, win_rate: null },
            unknown: { played: 0, wins: 0, win_rate: null },
        },
    };
    for (const fight of fights) {
        const result = classifyFightResult(fight, userId);
        if (!result.counted) {
            record.excluded++;
            continue;
        }
        record.played++;
        record.categories[fight.category].played++;
        if (result.result === "win") {
            record.wins++;
            record.categories[fight.category].wins++;
        }
    }
    for (const counts of [record, ...Object.values(record.categories)]) {
        counts.win_rate = counts.played > 0 ? counts.wins / counts.played : null;
    }
    return record;
}

export function rivalryRecord(fights: FightRecordFact[], viewerId: string, targetId: string): RivalryRecord {
    const record: RivalryRecord = { wins: 0, losses: 0, draws: 0, rematch: null };
    for (const fight of fights) {
        const viewer = classifyFightResult(fight, viewerId);
        const target = classifyFightResult(fight, targetId);
        if (viewer.fieldSize !== 2 || !viewer.counted || !target.counted) continue;
        if (viewer.result === "win") record.wins++;
        else if (target.result === "win") record.losses++;
        else record.draws++;
        if (record.rematch === null) {
            record.rematch = {
                duration_seconds: Math.round((Date.parse(fight.ends_at) - Date.parse(fight.starts_at)) / 1000),
                action_text: fight.action_text,
            };
        }
    }
    return record;
}
