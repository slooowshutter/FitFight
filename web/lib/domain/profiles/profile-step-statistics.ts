import type { ProfileActivityDay } from "@/lib/types/profiles/shared-profile";
import {
    profileActivityLevelValues, profileActivityMinimumSteps,
    type FriendComparison, type ProfileStatisticsContext, type ProfileStepStatistics, type StepTotals, type TenKStreak,
} from "@/lib/types/profiles/profile-step-statistics";

/** Only finalized civil days count. Gaps and partial days cannot establish a streak or a zero. */
export function profileStepStatistics(
    values: ProfileActivityDay[], context: ProfileStatisticsContext, scopeDays: 7 | 30 | null,
): ProfileStepStatistics {
    const dayMillis = 86_400_000;
    const today = Date.parse(`${context.today}T00:00:00Z`);
    const through = new Date(today - dayMillis).toISOString().slice(0, 10);
    const weekStart = today - ((new Date(today).getUTCDay() + 6) % 7) * dayMillis;
    const firstAllowed = scopeDays === null ? null : new Date(today - (scopeDays - 1) * dayMillis).toISOString().slice(0, 10);
    const recorded = values.filter((day) => day.finalized && day.time_zone !== null
        && day.day < context.today && (firstAllowed === null || day.day >= firstAllowed))
        .sort((left, right) => left.day.localeCompare(right.day));
    const from = firstAllowed ?? recorded[0]?.day ?? null;
    const yesterdayKnown = recorded.at(-1)?.day === through;
    const result: ProfileStepStatistics = {
        scope_days: scopeDays, from, through, time_zone: context.time_zone,
        recorded_days: recorded.length,
        unknown_days: from === null ? 0 : Math.max(0, Math.round((today - Date.parse(`${from}T00:00:00Z`)) / dayMillis) - recorded.length),
        total_steps: 0, average_steps: null, best_day: null,
        week: {
            starts_on: new Date(weekStart).toISOString().slice(0, 10),
            elapsed_days: (today - weekStart) / dayMillis,
            recorded_days: 0, total_steps: 0, average_steps: null,
        },
        levels: profileActivityLevelValues.map((level, index) => ({
            level, minimum_steps: profileActivityMinimumSteps[index], days: 0, share: null,
            longest_streak: 0, current_streak: yesterdayKnown ? 0 : null,
        })),
    };
    let previousDay = 0;
    let previousLevel = -1;
    let streak = 0;
    for (const day of recorded) {
        const date = Date.parse(`${day.day}T00:00:00Z`);
        const levelIndex = profileActivityMinimumSteps.findLastIndex((minimum) => day.steps >= minimum);
        const level = result.levels[levelIndex];
        streak = date - previousDay === dayMillis && previousLevel === levelIndex ? streak + 1 : 1;
        level.days += 1;
        level.longest_streak = Math.max(level.longest_streak, streak);
        if (day.day === through) level.current_streak = streak;
        result.total_steps += day.steps;
        if (result.best_day === null || day.steps > result.best_day.steps) {
            result.best_day = { day: day.day, steps: day.steps };
        }
        if (date >= weekStart) {
            result.week.recorded_days += 1;
            result.week.total_steps += day.steps;
        }
        previousDay = date;
        previousLevel = levelIndex;
    }
    if (recorded.length > 0) {
        result.average_steps = result.total_steps / recorded.length;
        for (const level of result.levels) level.share = level.days / recorded.length;
    }
    if (result.week.recorded_days > 0) result.week.average_steps = result.week.total_steps / result.week.recorded_days;
    return result;
}

/**
 * A run of consecutive 10,000-step days ending today, yesterday, or, while yesterday still waits for
 * its final sync, the day before. Any stored value of 10,000 counts, even before the day is final.
 */
export function tenKStreak(values: ProfileActivityDay[], today: string, owner: boolean): TenKStreak {
    const goal = 10_000;
    const dayMillis = 86_400_000;
    const todayMillis = Date.parse(`${today}T00:00:00Z`);
    const byDay = new Map(values.map((day) => [day.day, day]));
    const dayBefore = (offset: number) => new Date(todayMillis - offset * dayMillis).toISOString().slice(0, 10);
    const hit = (offset: number) => (byDay.get(dayBefore(offset))?.steps ?? 0) >= goal;
    const start = hit(0) ? 0 : hit(1) || byDay.get(dayBefore(1))?.finalized ? 1 : 2;
    let current = 0;
    while (hit(start + current)) current++;
    let best: TenKStreak["best"] = null;
    let run = 0;
    let previous = Number.NaN;
    for (const day of values.filter((value) => value.day <= today && value.steps >= goal).sort((left, right) => left.day.localeCompare(right.day))) {
        const date = Date.parse(`${day.day}T00:00:00Z`);
        run = date - previous === dayMillis ? run + 1 : 1;
        if (best === null || run > best.days) {
            best = { days: run, from: new Date(date - (run - 1) * dayMillis).toISOString().slice(0, 10), through: day.day };
        }
        previous = date;
    }
    return {
        goal, current, today_counted: hit(0),
        best: owner ? best : null,
        recent: owner ? Array.from({ length: 13 }, (_, index) => {
            const day = dayBefore(13 - index);
            return { day, steps: byDay.get(day)?.steps ?? null };
        }) : null,
    };
}

/** Finalized days from `since` through yesterday, the same days `profileStepStatistics` counts. */
export function friendComparison(yours: ProfileActivityDay[], theirs: ProfileActivityDay[], since: string, today: string): FriendComparison {
    const [you, them] = [yours, theirs].map((values) => {
        const totals: StepTotals = { recorded_days: 0, total_steps: 0, average_steps: null, best_day_steps: null, ten_k_days: 0 };
        for (const day of values) {
            if (!day.finalized || day.time_zone === null || day.day < since || day.day >= today) continue;
            totals.recorded_days++;
            totals.total_steps += day.steps;
            totals.best_day_steps = Math.max(totals.best_day_steps ?? 0, day.steps);
            if (day.steps >= 10_000) totals.ten_k_days++;
        }
        if (totals.recorded_days > 0) totals.average_steps = totals.total_steps / totals.recorded_days;
        return totals;
    });
    const days = Math.max(0, Math.round((Date.parse(`${today}T00:00:00Z`) - Date.parse(`${since}T00:00:00Z`)) / 86_400_000));
    return { since, days, you, them };
}
