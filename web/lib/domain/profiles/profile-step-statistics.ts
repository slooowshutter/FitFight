import type { ProfileActivityDay } from "@/lib/types/profiles/shared-profile";
import {
    profileActivityLevelValues, profileActivityMinimumSteps,
    type ProfileStatisticsContext, type ProfileStepStatistics,
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
