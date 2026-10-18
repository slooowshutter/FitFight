import type { ClassifiedFightResult, FightRecordFact, HeadToHeadResult } from "@/lib/types/profiles/profile-results";
import type { HeadToHead, ProfileRecord, RivalryRecord } from "@/lib/types/profiles/shared-profile";

/** Uses frozen ranks and participation evidence. */
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
    // Summaries frozen before 15 Oct 2026 lack rank_one_finishers: a missing final sync forfeited,
    // and nobody completing was a draw.
    if (fight.summary && fight.summary.rank_one_finishers === undefined) {
        const result = fight.summary.complete_finishers === 0
            ? "draw"
            : !member.complete
                ? "incomplete"
                : member.rank !== 1
                    ? "loss"
                    : fight.summary.first_place_finishers === 1 ? "win" : "draw";
        return { ...excluded, counted: true, result };
    }
    const firstPlaces = fight.summary?.rank_one_finishers ?? finishers.filter((item) => item.rank === 1).length;
    const result = member.rank !== 1 ? "loss" : firstPlaces === 1 ? "win" : "draw";
    return { ...excluded, counted: true, result };
}

export function profileRecord(fights: FightRecordFact[], userId: string): ProfileRecord {
    const record: ProfileRecord = {
        played: 0, wins: 0, draws: 0, losses: 0, win_rate: null, excluded: 0,
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
        } else if (result.result === "draw") {
            record.draws++;
        }
    }
    record.losses = record.played - record.wins - record.draws;
    for (const counts of [record, ...Object.values(record.categories)]) {
        counts.win_rate = counts.played > 0 ? counts.wins / counts.played : null;
    }
    return record;
}

/** Historical scores survive departure, but rematch details require current shared membership. */
export function rivalryRecord(fights: FightRecordFact[], viewerId: string, targetId: string, sharedFightIds: ReadonlySet<string>): RivalryRecord {
    const record: RivalryRecord = { wins: 0, losses: 0, draws: 0, rematch: null };
    for (const fight of fights) {
        const viewer = classifyFightResult(fight, viewerId);
        const target = classifyFightResult(fight, targetId);
        if (viewer.fieldSize !== 2 || !viewer.counted || !target.counted) continue;
        if (viewer.result === "win") record.wins++;
        else if (target.result === "win") record.losses++;
        else record.draws++;
        if (record.rematch === null && sharedFightIds.has(fight.id)) {
            record.rematch = {
                duration_seconds: Math.round((Date.parse(fight.ends_at) - Date.parse(fight.starts_at)) / 1000),
                duration_days: Number.isInteger(fight.calendar_days) && fight.calendar_days > 0 ? fight.calendar_days : null,
                action_text: fight.action_text,
            };
        }
    }
    return record;
}

/**
 * The viewer's result against the target in one finished Fight. In a group the better place wins;
 * a withdrawal or incomplete finish places behind everyone who finished.
 */
export function headToHeadResult(fight: FightRecordFact, viewerId: string, targetId: string): HeadToHeadResult | null {
    const [viewer, target] = [classifyFightResult(fight, viewerId), classifyFightResult(fight, targetId)];
    if (!viewer.counted || !target.counted) return null;
    if (viewer.fieldSize === 2) return viewer.result === "win" ? "win" : target.result === "win" ? "loss" : "draw";
    const [mine, theirs] = [viewer, target].map((result) => ["withdrawn", "incomplete"].includes(result.result)
        ? Number.POSITIVE_INFINITY
        : result.placement ?? Number.POSITIVE_INFINITY);
    return mine < theirs ? "win" : mine > theirs ? "loss" : "draw";
}

/** `fights` are the Fights both people are still members of, newest first. */
export function headToHeadRecord(fights: FightRecordFact[], viewerId: string, targetId: string): HeadToHead {
    const results = fights.flatMap((fight) => headToHeadResult(fight, viewerId, targetId) ?? []);
    return {
        wins: results.filter((result) => result === "win").length,
        draws: results.filter((result) => result === "draw").length,
        losses: results.filter((result) => result === "loss").length,
        form: results.slice(0, 10).reverse(),
    };
}
