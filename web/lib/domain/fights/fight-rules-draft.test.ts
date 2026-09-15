import assert from "node:assert/strict";
import { test } from "node:test";
import {
    fightRulesDraftSchema,
    type FightRulesDraft,
} from "../../types/fights/fight-rules-draft";

const mostSteps = {
    schemaVersion: 1,
    status: "draft",
    window: {
        startsAt: "2026-10-05T00:00:00+02:00",
        endsAt: "2026-10-12T00:00:00+02:00",
        timeZone: "Europe/Paris",
        partialDays: "reject",
        dailyAverageDenominator: "scheduled_days",
    },
    lateJoin: "closed",
    personalTargets: [],
    measures: [
        {
            id: "steps",
            definition: { id: "apple_health_merged_steps", version: 1 },
            unit: "steps",
            sourcePolicy: "one_selected_source_per_member",
            workouts: null,
        },
    ],
    scores: [
        {
            id: "total_steps",
            type: "measured",
            measureId: "steps",
            subject: "member",
            buckets: "fight",
            withinBucket: { type: "aggregate", operation: "total" },
            reduction: { type: "aggregate", operation: "total" },
            unit: "steps",
        },
    ],
    conditions: [],
    result: {
        type: "ranking",
        scoreId: "total_steps",
        direction: "higher",
        eligibilityConditionId: null,
        zones: [
            { edge: "top", from: 1, to: 1, outcome: "win", label: "Winner" },
        ],
        ties: "shared",
        overlappingZones: "neutral",
    },
    stake: { actions: [], money: null },
    allocation: null,
    finalization: {
        graceSeconds: 86_400,
        incomplete: "forfeit",
        allIncomplete: "draw_cancel_obligations",
        allEligibleScoresZero: "draw_return_contributions",
        withdrawal: "ineligible",
        cancellation: "cancel_obligations_return_contributions",
    },
} satisfies FightRulesDraft;

const dailyGoal = {
    ...mostSteps,
    scores: [
        {
            ...mostSteps.scores[0],
            id: "daily_average",
            buckets: "day",
            reduction: { type: "aggregate", operation: "average" },
            unit: "steps_per_day",
        },
        {
            ...mostSteps.scores[0],
            id: "best_day",
            buckets: "day",
            reduction: { type: "aggregate", operation: "maximum" },
        },
    ],
    conditions: [
        {
            id: "average_met",
            type: "comparison",
            scoreId: "daily_average",
            comparison: {
                type: "threshold",
                unit: "steps_per_day",
                operator: "gte",
                target: { type: "fixed", value: 8_000 },
            },
        },
        {
            id: "big_day_met",
            type: "comparison",
            scoreId: "best_day",
            comparison: {
                type: "threshold",
                unit: "steps",
                operator: "gte",
                target: { type: "fixed", value: 15_000 },
            },
        },
        {
            id: "both_met",
            type: "all",
            conditionIds: ["average_met", "big_day_met"],
        },
    ],
    result: { type: "goal", conditionId: "both_met", scope: "each_member" },
} satisfies FightRulesDraft;

const prizeFight = {
    ...mostSteps,
    result: {
        ...mostSteps.result,
        zones: [
            { edge: "top", from: 1, to: 3, outcome: "win", label: "Podium" },
        ],
    },
    stake: {
        actions: [],
        money: {
            currency: "EUR",
            contributors: { type: "all_members" },
            contribution: { type: "fixed", minorUnits: 1000 },
            forfeitedContribution: "still_owed",
            withdrawnContribution: "still_owed",
        },
    },
    allocation: {
        recipients: { type: "outcome", outcome: "win" },
        method: {
            type: "rank_weights",
            ranking: "among_recipients",
            basisPoints: [5000, 3000, 2000],
            ties: "pool_occupied_positions",
        },
        rounding: "largest_remainder_then_member_id",
        noRecipients: "return_contributions",
        zeroWeight: "return_contributions",
        remainder: "return_to_contributors_proportionally",
    },
} satisfies FightRulesDraft;

test("draft rules express Most Steps, compound daily goals, and a 50/30/20 podium", () => {
    for (const example of [mostSteps, dailyGoal, prizeFight]) {
        assert.deepEqual(fightRulesDraftSchema.parse(example), example);
    }
});

test("bottom three can jointly owe one action without changing score direction", () => {
    const rule: FightRulesDraft = {
        ...mostSteps,
        result: {
            ...mostSteps.result,
            zones: [
                {
                    edge: "bottom",
                    from: 1,
                    to: 3,
                    outcome: "lose",
                    label: "Dinner crew",
                },
            ],
        },
        stake: {
            money: null,
            actions: [
                {
                    id: "dinner",
                    liable: { type: "outcome", outcome: "lose" },
                    responsibility: "joint",
                    text: "Organize one dinner",
                    beneficiaries: { type: "all_members" },
                    dueAt: null,
                },
            ],
        },
    };
    assert.deepEqual(fightRulesDraftSchema.parse(rule), rule);
});

test("proportional shares can select the top two independently of the winning zone", () => {
    const rule: FightRulesDraft = {
        ...prizeFight,
        result: mostSteps.result,
        allocation: {
            ...prizeFight.allocation,
            recipients: {
                type: "ranked",
                edge: "top",
                count: 2,
                boundaryTies: "include_all",
            },
            method: { type: "score_weights", scoreId: "total_steps" },
        },
    };
    assert.deepEqual(fightRulesDraftSchema.parse(rule), rule);
});

test("shared mountain combines a group total with every member's minimum contribution", () => {
    const rule: FightRulesDraft = {
        ...mostSteps,
        scores: [
            mostSteps.scores[0],
            { ...mostSteps.scores[0], id: "group_total", subject: "group" },
        ],
        conditions: [
            {
                id: "individual_floor",
                type: "comparison",
                scoreId: "total_steps",
                comparison: {
                    type: "threshold",
                    unit: "steps",
                    operator: "gte",
                    target: { type: "fixed", value: 10_000 },
                },
            },
            {
                id: "everyone_contributed",
                type: "members",
                conditionId: "individual_floor",
                requirement: { type: "all" },
            },
            {
                id: "group_target",
                type: "comparison",
                scoreId: "group_total",
                comparison: {
                    type: "threshold",
                    unit: "steps",
                    operator: "gte",
                    target: { type: "fixed", value: 100_000 },
                },
            },
            {
                id: "mountain",
                type: "all",
                conditionIds: ["everyone_contributed", "group_target"],
            },
        ],
        result: { type: "goal", conditionId: "mountain", scope: "group" },
    };
    assert.deepEqual(fightRulesDraftSchema.parse(rule), rule);
    const mixedScopes = {
        ...rule,
        conditions: [
            ...rule.conditions.slice(0, -1),
            {
                id: "mountain",
                type: "all",
                conditionIds: ["individual_floor", "group_target"],
            },
        ],
    };
    assert.equal(fightRulesDraftSchema.safeParse(mixedScopes).success, false);
});

test("successful-day counts and streaks use days rather than Steps", () => {
    for (const type of ["count_matching", "longest_streak"] as const) {
        const score = {
            ...mostSteps.scores[0],
            buckets: "day",
            unit: "days",
            reduction: {
                type,
                comparison: {
                    type: "threshold",
                    unit: "steps",
                    operator: "gte",
                    target: { type: "fixed", value: 10_000 },
                },
            },
        };
        assert.equal(
            fightRulesDraftSchema.safeParse({ ...mostSteps, scores: [score] })
                .success,
            true,
        );
        assert.equal(
            fightRulesDraftSchema.safeParse({
                ...mostSteps,
                scores: [{ ...score, unit: "steps" }],
            }).success,
            false,
        );
        if (type === "longest_streak") {
            assert.equal(
                fightRulesDraftSchema.safeParse({
                    ...mostSteps,
                    scores: [
                        { ...score, buckets: "workout", unit: "workouts" },
                    ],
                }).success,
                false,
            );
        }
    }
});

test("workout days and sustained intensity use qualification and duration explicitly", () => {
    const workoutRules = {
        activityTypes: ["running"],
        minimumMinutes: 20,
        durationBasis: "active",
        manualEntries: "exclude",
        overlapping: "deduplicate",
        mergeGapMinutes: 10,
        maximumPerDay: null,
        dayAssignment: "start_day",
        windowBoundary: "wholly_inside",
    } satisfies NonNullable<FightRulesDraft["measures"][number]["workouts"]>;
    const workouts: FightRulesDraft = {
        ...mostSteps,
        measures: [
            {
                ...mostSteps.measures[0],
                id: "sessions",
                definition: { id: "qualified_workout_count", version: 1 },
                unit: "workouts",
                workouts: workoutRules,
            },
        ],
        scores: [
            {
                ...mostSteps.scores[0],
                measureId: "sessions",
                buckets: "day",
                unit: "days",
                reduction: {
                    type: "count_matching",
                    comparison: {
                        type: "threshold",
                        unit: "workouts",
                        operator: "gte",
                        target: { type: "fixed", value: 1 },
                    },
                },
            },
        ],
    };
    assert.deepEqual(fightRulesDraftSchema.parse(workouts), workouts);
    const sustainedEffort: FightRulesDraft = {
        ...mostSteps,
        measures: [
            {
                ...mostSteps.measures[0],
                id: "intensity",
                definition: { id: "provider_intensity", version: 1 },
                unit: "intensity_points",
                workouts: workoutRules,
            },
        ],
        scores: [
            {
                ...mostSteps.scores[0],
                measureId: "intensity",
                buckets: "workout",
                unit: "minutes",
                withinBucket: {
                    type: "time_matching",
                    duration: "longest_contiguous",
                    comparison: {
                        type: "threshold",
                        unit: "intensity_points",
                        operator: "gte",
                        target: { type: "fixed", value: 10 },
                    },
                },
                reduction: { type: "aggregate", operation: "maximum" },
            },
        ],
    };
    assert.deepEqual(
        fightRulesDraftSchema.parse(sustainedEffort),
        sustainedEffort,
    );
});

test("best days, daily caps, daily wins, target deviation, and baseline improvement are expressible", () => {
    for (const reduction of [
        { type: "best_n_total", count: 2 },
        { type: "capped_total", cap: 12_000 },
        { type: "daily_wins", tiedLeaders: "split_one_win", allZero: "no_win" },
    ] as const) {
        assert.equal(
            fightRulesDraftSchema.safeParse({
                ...mostSteps,
                scores: [
                    {
                        ...mostSteps.scores[0],
                        buckets: "day",
                        reduction,
                        unit:
                            reduction.type === "daily_wins" ? "wins" : "steps",
                    },
                ],
            }).success,
            true,
        );
    }
    for (const derived of [
        {
            id: "derived",
            type: "deviation",
            scoreId: "total_steps",
            target: 50_000,
            unit: "steps",
        },
        {
            id: "derived",
            type: "improvement",
            scoreId: "total_steps",
            method: "percentage",
            unit: "percent",
            zeroBaseline: "ineligible",
            baseline: {
                startsAt: "2026-09-28T00:00:00+02:00",
                endsAt: "2026-10-05T00:00:00+02:00",
                coverage: "complete",
            },
        },
    ] satisfies FightRulesDraft["scores"]) {
        assert.equal(
            fightRulesDraftSchema.safeParse({
                ...mostSteps,
                scores: [mostSteps.scores[0], derived],
                result: { ...mostSteps.result, scoreId: "derived" },
            }).success,
            true,
        );
    }
});

test("personal targets are explicit and cannot set a competitive ranking threshold", () => {
    const rule = {
        ...dailyGoal,
        personalTargets: [
            {
                id: "my_average",
                unit: "steps_per_day",
                minimum: 1000,
                maximum: 20000,
            },
        ],
        conditions: [
            {
                ...dailyGoal.conditions[0],
                comparison: {
                    type: "threshold",
                    unit: "steps_per_day",
                    operator: "gte",
                    target: { type: "personal", targetId: "my_average" },
                },
            },
        ],
        result: {
            type: "goal",
            conditionId: "average_met",
            scope: "each_member",
        },
    };
    assert.equal(fightRulesDraftSchema.safeParse(rule).success, true);
    assert.equal(
        fightRulesDraftSchema.safeParse({ ...rule, personalTargets: [] })
            .success,
        false,
    );
    assert.equal(
        fightRulesDraftSchema.safeParse({
            ...rule,
            result: { ...mostSteps.result, scoreId: "daily_average" },
        }).success,
        false,
    );
});

test("unknown fields, missing references, cycles, and repeated clauses fail at the draft boundary", () => {
    const invalid = [
        { ...mostSteps, formula: "run_code()" },
        {
            ...mostSteps,
            scores: [{ ...mostSteps.scores[0], measureId: "missing" }],
        },
        { ...mostSteps, scores: [mostSteps.scores[0], mostSteps.scores[0]] },
        {
            ...dailyGoal,
            conditions: [
                ...dailyGoal.conditions.slice(0, 2),
                {
                    id: "both_met",
                    type: "all",
                    conditionIds: ["average_met", "average_met"],
                },
            ],
        },
        {
            ...dailyGoal,
            conditions: [
                { id: "both_met", type: "all", conditionIds: ["both_met"] },
            ],
        },
        {
            ...dailyGoal,
            conditions: [
                { id: "both_met", type: "all", conditionIds: ["other"] },
                { id: "other", type: "any", conditionIds: ["both_met"] },
            ],
        },
        {
            ...mostSteps,
            scores: [
                {
                    id: "total_steps",
                    type: "deviation",
                    scoreId: "total_steps",
                    target: 10,
                    unit: "steps",
                },
            ],
        },
        {
            ...dailyGoal,
            conditions: [
                ...dailyGoal.conditions.slice(0, 2),
                {
                    id: "both_met",
                    type: "at_least",
                    count: 3,
                    conditionIds: ["average_met", "big_day_met"],
                },
            ],
        },
    ];
    for (const rule of invalid)
        assert.equal(fightRulesDraftSchema.safeParse(rule).success, false);
});

test("units, ranges, time zones, chronology, and non-finite values are validated", () => {
    const invalid = [
        {
            ...mostSteps,
            window: { ...mostSteps.window, timeZone: "Nowhere/Invalid" },
        },
        {
            ...mostSteps,
            window: { ...mostSteps.window, endsAt: mostSteps.window.startsAt },
        },
        { ...mostSteps, scores: [{ ...mostSteps.scores[0], unit: "minutes" }] },
        {
            ...dailyGoal,
            conditions: [
                {
                    id: "both_met",
                    type: "comparison",
                    scoreId: "best_day",
                    comparison: {
                        type: "range",
                        unit: "steps",
                        minimum: 20000,
                        maximum: 10000,
                    },
                },
            ],
        },
        {
            ...dailyGoal,
            conditions: [
                {
                    id: "both_met",
                    type: "comparison",
                    scoreId: "best_day",
                    comparison: {
                        type: "threshold",
                        unit: "steps",
                        operator: "gte",
                        target: { type: "fixed", value: Infinity },
                    },
                },
            ],
        },
    ];
    for (const rule of invalid)
        assert.equal(fightRulesDraftSchema.safeParse(rule).success, false);
});

test("money requires a complete allocation and exact rank percentages", () => {
    for (const rule of [
        { ...prizeFight, allocation: null },
        { ...mostSteps, allocation: prizeFight.allocation },
        {
            ...prizeFight,
            allocation: {
                ...prizeFight.allocation,
                method: {
                    ...prizeFight.allocation.method,
                    basisPoints: [5000, 3000],
                },
            },
        },
        {
            ...prizeFight,
            allocation: {
                ...prizeFight.allocation,
                method: { type: "score_weights", scoreId: "missing" },
            },
        },
        {
            ...prizeFight,
            stake: {
                ...prizeFight.stake,
                money: {
                    ...prizeFight.stake.money,
                    contribution: { type: "fixed", minorUnits: 10.5 },
                },
            },
        },
        {
            ...dailyGoal,
            stake: {
                money: null,
                actions: [
                    {
                        id: "dinner",
                        liable: { type: "outcome", outcome: "lose" },
                        beneficiaries: { type: "all_members" },
                        responsibility: "each",
                        text: "Cook",
                        dueAt: null,
                    },
                ],
            },
        },
    ])
        assert.equal(fightRulesDraftSchema.safeParse(rule).success, false);
});
