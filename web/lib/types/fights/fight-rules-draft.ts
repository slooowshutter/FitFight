import { z } from "zod";

const identifierSchema = z
    .string()
    .regex(/^[a-z][a-z0-9_]*$/)
    .max(80);
const finiteNumberSchema = z.number().finite();
const countSchema = z.number().int().positive().safe();
const minorUnitsSchema = z.number().int().nonnegative().safe();
const unitSchema = z.string().trim().min(1).max(80);
const instantSchema = z.string().datetime({ offset: true });

const comparisonOperatorValues = ["gt", "gte", "lt", "lte", "eq"] as const;
const aggregationValues = [
    "total",
    "average",
    "minimum",
    "maximum",
    "count",
] as const;
const rankingOutcomeValues = ["win", "lose", "safe"] as const;
const outcomeValues = [...rankingOutcomeValues, "success", "failure"] as const;
const durationBasisValues = ["active", "elapsed"] as const;
const manualEntryPolicyValues = ["include", "exclude"] as const;
const workoutDayAssignmentValues = ["start_day", "split_at_midnight"] as const;
const workoutBoundaryValues = ["wholly_inside", "clip_to_window"] as const;
const dailyWinTieValues = ["one_win_each", "split_one_win"] as const;
const scoreSubjectValues = ["member", "group"] as const;
const scoreBucketValues = ["fight", "day", "workout"] as const;
const matchingDurationValues = ["cumulative", "longest_contiguous"] as const;
const improvementMethodValues = ["absolute", "percentage"] as const;
const rankEdgeValues = ["top", "bottom"] as const;
const rankDirectionValues = ["higher", "lower"] as const;
const goalScopeValues = ["each_member", "every_member", "group"] as const;
const actionResponsibilityValues = ["each", "joint"] as const;
const contributionLiabilityValues = ["still_owed", "cancel"] as const;
const insufficientPoolPolicyValues = ["prorate", "void_allocation"] as const;
const partialDayPolicyValues = ["include", "exclude", "reject"] as const;
const lateJoinPolicyValues = ["full_window", "closed"] as const;
const incompletePolicyValues = ["forfeit", "void_fight"] as const;
const allZeroPolicyValues = [
    "apply_result",
    "draw_return_contributions",
] as const;

const targetSchema = z.discriminatedUnion("type", [
    z.object({ type: z.literal("fixed"), value: finiteNumberSchema }).strict(),
    z
        .object({ type: z.literal("personal"), targetId: identifierSchema })
        .strict(),
]);

const comparisonSchema = z.discriminatedUnion("type", [
    z
        .object({
            type: z.literal("threshold"),
            unit: unitSchema,
            operator: z.enum(comparisonOperatorValues),
            target: targetSchema,
        })
        .strict(),
    z
        .object({
            type: z.literal("range"),
            unit: unitSchema,
            minimum: finiteNumberSchema,
            maximum: finiteNumberSchema,
        })
        .strict(),
]);

const measureSchema = z
    .object({
        id: identifierSchema,
        definition: z
            .object({ id: identifierSchema, version: countSchema })
            .strict(),
        unit: unitSchema,
        sourcePolicy: z.literal("one_selected_source_per_member"),
        workouts: z
            .object({
                activityTypes: z.array(identifierSchema).min(1),
                minimumMinutes: finiteNumberSchema.nonnegative(),
                durationBasis: z.enum(durationBasisValues),
                manualEntries: z.enum(manualEntryPolicyValues),
                overlapping: z.literal("deduplicate"),
                mergeGapMinutes: finiteNumberSchema.nonnegative(),
                maximumPerDay: countSchema.nullable(),
                dayAssignment: z.enum(workoutDayAssignmentValues),
                windowBoundary: z.enum(workoutBoundaryValues),
            })
            .strict()
            .nullable(),
    })
    .strict();

const reductionSchema = z.discriminatedUnion("type", [
    z
        .object({
            type: z.literal("aggregate"),
            operation: z.enum(aggregationValues),
        })
        .strict(),
    z.object({ type: z.literal("best_n_total"), count: countSchema }).strict(),
    z
        .object({
            type: z.literal("capped_total"),
            cap: finiteNumberSchema.nonnegative(),
        })
        .strict(),
    z
        .object({
            type: z.literal("count_matching"),
            comparison: comparisonSchema,
        })
        .strict(),
    z
        .object({
            type: z.literal("longest_streak"),
            comparison: comparisonSchema,
        })
        .strict(),
    z
        .object({
            type: z.literal("daily_wins"),
            tiedLeaders: z.enum(dailyWinTieValues),
            allZero: z.literal("no_win"),
        })
        .strict(),
]);

const scoreSchema = z.discriminatedUnion("type", [
    z
        .object({
            id: identifierSchema,
            type: z.literal("measured"),
            measureId: identifierSchema,
            subject: z.enum(scoreSubjectValues),
            buckets: z.enum(scoreBucketValues),
            withinBucket: z.discriminatedUnion("type", [
                z
                    .object({
                        type: z.literal("aggregate"),
                        operation: z.enum(aggregationValues),
                    })
                    .strict(),
                z
                    .object({
                        type: z.literal("time_matching"),
                        comparison: comparisonSchema,
                        duration: z.enum(matchingDurationValues),
                    })
                    .strict(),
            ]),
            reduction: reductionSchema,
            unit: unitSchema,
        })
        .strict(),
    z
        .object({
            id: identifierSchema,
            type: z.literal("deviation"),
            scoreId: identifierSchema,
            target: finiteNumberSchema,
            unit: unitSchema,
        })
        .strict(),
    z
        .object({
            id: identifierSchema,
            type: z.literal("improvement"),
            scoreId: identifierSchema,
            baseline: z
                .object({
                    startsAt: instantSchema,
                    endsAt: instantSchema,
                    coverage: z.literal("complete"),
                })
                .strict(),
            method: z.enum(improvementMethodValues),
            zeroBaseline: z.literal("ineligible"),
            unit: unitSchema,
        })
        .strict(),
]);

// Named references allow schema-derived types without an unbounded recursive formula tree.
const conditionSchema = z.discriminatedUnion("type", [
    z
        .object({
            id: identifierSchema,
            type: z.literal("comparison"),
            scoreId: identifierSchema,
            comparison: comparisonSchema,
        })
        .strict(),
    z
        .object({
            id: identifierSchema,
            type: z.literal("all"),
            conditionIds: z.array(identifierSchema).min(1).max(32),
        })
        .strict(),
    z
        .object({
            id: identifierSchema,
            type: z.literal("any"),
            conditionIds: z.array(identifierSchema).min(1).max(32),
        })
        .strict(),
    z
        .object({
            id: identifierSchema,
            type: z.literal("at_least"),
            count: countSchema,
            conditionIds: z.array(identifierSchema).min(1).max(32),
        })
        .strict(),
    z
        .object({
            id: identifierSchema,
            type: z.literal("members"),
            conditionId: identifierSchema,
            requirement: z.discriminatedUnion("type", [
                z.object({ type: z.literal("all") }).strict(),
                z.object({ type: z.literal("any") }).strict(),
                z
                    .object({ type: z.literal("at_least"), count: countSchema })
                    .strict(),
            ]),
        })
        .strict(),
]);

const selectionSchema = z.discriminatedUnion("type", [
    z.object({ type: z.literal("all_members") }).strict(),
    z
        .object({ type: z.literal("outcome"), outcome: z.enum(outcomeValues) })
        .strict(),
    z
        .object({
            type: z.literal("ranked"),
            edge: z.enum(rankEdgeValues),
            count: countSchema,
            boundaryTies: z.literal("include_all"),
        })
        .strict(),
]);

const resultSchema = z.discriminatedUnion("type", [
    z
        .object({
            type: z.literal("ranking"),
            scoreId: identifierSchema,
            direction: z.enum(rankDirectionValues),
            eligibilityConditionId: identifierSchema.nullable(),
            zones: z
                .array(
                    z
                        .object({
                            edge: z.enum(rankEdgeValues),
                            from: countSchema,
                            to: countSchema,
                            outcome: z.enum(rankingOutcomeValues),
                            label: z.string().trim().min(1).max(80),
                        })
                        .strict(),
                )
                .max(16),
            ties: z.literal("shared"),
            overlappingZones: z.literal("neutral"),
        })
        .strict(),
    z
        .object({
            type: z.literal("goal"),
            conditionId: identifierSchema,
            scope: z.enum(goalScopeValues),
        })
        .strict(),
]);

const stakeSchema = z
    .object({
        actions: z
            .array(
                z
                    .object({
                        id: identifierSchema,
                        liable: selectionSchema,
                        responsibility: z.enum(actionResponsibilityValues),
                        text: z.string().trim().min(1).max(500),
                        beneficiaries: selectionSchema,
                        dueAt: instantSchema.nullable(),
                    })
                    .strict(),
            )
            .max(16),
        money: z
            .object({
                currency: z.string().regex(/^[A-Z]{3}$/),
                contributors: selectionSchema,
                contribution: z.discriminatedUnion("type", [
                    z
                        .object({
                            type: z.literal("fixed"),
                            minorUnits: minorUnitsSchema,
                        })
                        .strict(),
                    z
                        .object({
                            type: z.literal("per_score_unit"),
                            scoreId: identifierSchema,
                            minorUnitsPerUnit: minorUnitsSchema,
                            maximumMinorUnitsPerMember: minorUnitsSchema,
                        })
                        .strict(),
                ]),
                forfeitedContribution: z.enum(contributionLiabilityValues),
                withdrawnContribution: z.enum(contributionLiabilityValues),
            })
            .strict()
            .nullable(),
    })
    .strict();

const allocationSchema = z
    .object({
        recipients: selectionSchema,
        method: z.discriminatedUnion("type", [
            z.object({ type: z.literal("equal") }).strict(),
            z
                .object({
                    type: z.literal("rank_weights"),
                    ranking: z.literal("among_recipients"),
                    basisPoints: z
                        .array(z.number().int().min(0).max(10_000))
                        .min(1)
                        .max(32),
                    ties: z.literal("pool_occupied_positions"),
                })
                .strict(),
            z
                .object({
                    type: z.literal("score_weights"),
                    scoreId: identifierSchema,
                })
                .strict(),
            z
                .object({
                    type: z.literal("fixed_award"),
                    minorUnitsPerRecipient: minorUnitsSchema,
                    insufficientPool: z.enum(insufficientPoolPolicyValues),
                })
                .strict(),
        ]),
        rounding: z.literal("largest_remainder_then_member_id"),
        noRecipients: z.literal("return_contributions"),
        zeroWeight: z.literal("return_contributions"),
        remainder: z.literal("return_to_contributors_proportionally"),
    })
    .strict();

/**
 * Draft single-round agreement, isolated from the installed app's API contract.
 * Parsing checks structure and references, not provider capability or launch approval.
 */
export const fightRulesDraftSchema = z
    .object({
        schemaVersion: z.literal(1),
        status: z.literal("draft"),
        window: z
            .object({
                startsAt: instantSchema,
                endsAt: instantSchema,
                timeZone: z.string().min(1),
                partialDays: z.enum(partialDayPolicyValues),
                dailyAverageDenominator: z.literal("scheduled_days"),
            })
            .strict(),
        lateJoin: z.enum(lateJoinPolicyValues),
        personalTargets: z
            .array(
                z
                    .object({
                        id: identifierSchema,
                        unit: unitSchema,
                        minimum: finiteNumberSchema,
                        maximum: finiteNumberSchema,
                    })
                    .strict(),
            )
            .max(32),
        measures: z.array(measureSchema).min(1).max(16),
        scores: z.array(scoreSchema).min(1).max(64),
        conditions: z.array(conditionSchema).max(64),
        result: resultSchema,
        stake: stakeSchema,
        allocation: allocationSchema.nullable(),
        finalization: z
            .object({
                graceSeconds: z.number().int().nonnegative().safe(),
                incomplete: z.enum(incompletePolicyValues),
                allIncomplete: z.literal("draw_cancel_obligations"),
                allEligibleScoresZero: z.enum(allZeroPolicyValues),
                withdrawal: z.literal("ineligible"),
                cancellation: z.literal(
                    "cancel_obligations_return_contributions",
                ),
            })
            .strict(),
    })
    .strict()
    .superRefine((rule, ctx) => {
        const issue = (path: (string | number)[], message: string) => {
            ctx.addIssue({ code: z.ZodIssueCode.custom, path, message });
        };
        for (const name of [
            "measures",
            "scores",
            "conditions",
            "personalTargets",
        ] as const) {
            const ids = rule[name].map((entry) => entry.id);
            if (new Set(ids).size !== ids.length)
                issue([name], "IDs must be unique within this collection");
        }
        if (
            new Set(rule.stake.actions.map((action) => action.id)).size !==
            rule.stake.actions.length
        ) {
            issue(["stake", "actions"], "Action IDs must be unique");
        }
        if (
            Date.parse(rule.window.endsAt) <= Date.parse(rule.window.startsAt)
        ) {
            issue(["window", "endsAt"], "Fight end must follow its start");
        }
        try {
            new Intl.DateTimeFormat("en", { timeZone: rule.window.timeZone });
        } catch {
            issue(["window", "timeZone"], "Unknown IANA time zone");
        }

        const measures = new Map(
            rule.measures.map((measure) => [measure.id, measure]),
        );
        const scores = new Map(rule.scores.map((score) => [score.id, score]));
        const conditions = new Map(
            rule.conditions.map((condition) => [condition.id, condition]),
        );
        const targets = new Map(
            rule.personalTargets.map((target) => [target.id, target]),
        );
        const comparisons: {
            comparison: z.infer<typeof comparisonSchema>;
            scoreId: string;
            unit: string;
            path: (string | number)[];
        }[] = [];

        rule.personalTargets.forEach((target, index) => {
            if (target.minimum > target.maximum)
                issue(["personalTargets", index], "Target bounds are reversed");
        });
        rule.scores.forEach((score, index) => {
            const path = ["scores", index];
            if (score.type !== "measured") {
                const source = scores.get(score.scoreId);
                if (!source) issue([...path, "scoreId"], "Unknown score");
                if (
                    source &&
                    score.unit !==
                        (score.type === "improvement" &&
                        score.method === "percentage"
                            ? "percent"
                            : source.unit)
                ) {
                    issue(
                        [...path, "unit"],
                        "Derived score has the wrong unit",
                    );
                }
                if (
                    score.type === "improvement" &&
                    (Date.parse(score.baseline.startsAt) >=
                        Date.parse(score.baseline.endsAt) ||
                        Date.parse(score.baseline.endsAt) >
                            Date.parse(rule.window.startsAt))
                ) {
                    issue(
                        [...path, "baseline"],
                        "Baseline must be non-empty and end before the Fight starts",
                    );
                }
                return;
            }
            const measure = measures.get(score.measureId);
            if (!measure) {
                issue([...path, "measureId"], "Unknown measure");
                return;
            }
            if (score.buckets === "workout" && measure.workouts === null) {
                issue(
                    [...path, "buckets"],
                    "Workout buckets require explicit workout qualification rules",
                );
            }
            const bucketUnit =
                score.withinBucket.type === "time_matching"
                    ? "minutes"
                    : score.withinBucket.operation === "count"
                      ? "observations"
                      : measure.unit;
            if (score.withinBucket.type === "time_matching") {
                comparisons.push({
                    comparison: score.withinBucket.comparison,
                    scoreId: score.id,
                    unit: measure.unit,
                    path: [...path, "withinBucket", "comparison"],
                });
            }
            const reduction = score.reduction;
            if (
                reduction.type === "count_matching" ||
                reduction.type === "longest_streak"
            ) {
                comparisons.push({
                    comparison: reduction.comparison,
                    scoreId: score.id,
                    unit: bucketUnit,
                    path: [...path, "reduction", "comparison"],
                });
            }
            if (
                (reduction.type === "longest_streak" ||
                    reduction.type === "daily_wins") &&
                score.buckets !== "day"
            ) {
                issue(
                    [...path, "buckets"],
                    "Streaks and daily wins require day buckets",
                );
            }
            if (reduction.type === "daily_wins" && score.subject !== "member") {
                issue(
                    [...path, "subject"],
                    "Daily wins compare individual members",
                );
            }
            const countedUnit =
                score.buckets === "day"
                    ? "days"
                    : score.buckets === "workout"
                      ? "workouts"
                      : "windows";
            const expectedUnit =
                reduction.type === "daily_wins"
                    ? "wins"
                    : reduction.type === "longest_streak" ||
                        reduction.type === "count_matching" ||
                        (reduction.type === "aggregate" &&
                            reduction.operation === "count")
                      ? countedUnit
                      : reduction.type === "aggregate" &&
                          reduction.operation === "average" &&
                          score.buckets === "day"
                        ? `${bucketUnit}_per_day`
                        : bucketUnit;
            if (score.unit !== expectedUnit)
                issue(
                    [...path, "unit"],
                    `Expected score unit: ${expectedUnit}`,
                );
        });
        rule.conditions.forEach((condition, index) => {
            if (condition.type === "comparison") {
                const score = scores.get(condition.scoreId);
                if (!score)
                    issue(["conditions", index, "scoreId"], "Unknown score");
                else
                    comparisons.push({
                        comparison: condition.comparison,
                        scoreId: score.id,
                        unit: score.unit,
                        path: ["conditions", index, "comparison"],
                    });
            } else if (condition.type === "members") {
                if (!conditions.has(condition.conditionId))
                    issue(
                        ["conditions", index, "conditionId"],
                        "Unknown member condition",
                    );
            } else {
                if (
                    new Set(condition.conditionIds).size !==
                    condition.conditionIds.length
                ) {
                    issue(
                        ["conditions", index, "conditionIds"],
                        "A condition cannot count the same clause twice",
                    );
                }
                for (const id of condition.conditionIds) {
                    if (!conditions.has(id))
                        issue(
                            ["conditions", index, "conditionIds"],
                            `Unknown condition: ${id}`,
                        );
                }
                if (
                    condition.type === "at_least" &&
                    condition.count > condition.conditionIds.length
                ) {
                    issue(
                        ["conditions", index, "count"],
                        "Required count exceeds the number of clauses",
                    );
                }
            }
        });
        for (const { comparison, unit, path } of comparisons) {
            if (comparison.unit !== unit)
                issue([...path, "unit"], `Expected comparison unit: ${unit}`);
            if (comparison.type === "range") {
                if (comparison.minimum > comparison.maximum)
                    issue(path, "Range bounds are reversed");
            } else if (comparison.target.type === "personal") {
                const target = targets.get(comparison.target.targetId);
                if (!target)
                    issue([...path, "target"], "Unknown personal target");
                else if (target.unit !== comparison.unit)
                    issue(
                        [...path, "target"],
                        "Personal target has the wrong unit",
                    );
                if (rule.result.type === "ranking")
                    issue(
                        path,
                        "Personal targets are restricted to goal Fights",
                    );
            }
        }

        for (const [name, graph] of [
            [
                "scores",
                new Map(
                    rule.scores.map((score) => [
                        score.id,
                        score.type === "measured" ? [] : [score.scoreId],
                    ]),
                ),
            ],
            [
                "conditions",
                new Map(
                    rule.conditions.map((condition) => [
                        condition.id,
                        condition.type === "comparison"
                            ? []
                            : condition.type === "members"
                              ? [condition.conditionId]
                              : condition.conditionIds,
                    ]),
                ),
            ],
        ] as const) {
            const resolved = new Set<string>();
            for (let pass = 0; pass < graph.size; pass += 1) {
                for (const [id, dependencies] of graph) {
                    if (
                        dependencies.every((dependency) =>
                            resolved.has(dependency),
                        )
                    )
                        resolved.add(id);
                }
            }
            if (resolved.size !== graph.size)
                issue(
                    [name],
                    "References must form an acyclic graph with no missing nodes",
                );
        }

        const scoreSubjects = new Map<
            string,
            (typeof scoreSubjectValues)[number]
        >();
        for (let pass = 0; pass < scores.size; pass += 1) {
            for (const score of rule.scores) {
                const subject =
                    score.type === "measured"
                        ? score.subject
                        : scoreSubjects.get(score.scoreId);
                if (subject !== undefined) scoreSubjects.set(score.id, subject);
            }
        }
        const conditionSubjects = new Map<
            string,
            (typeof scoreSubjectValues)[number]
        >();
        for (let pass = 0; pass < conditions.size; pass += 1) {
            for (const condition of rule.conditions) {
                const subject =
                    condition.type === "comparison"
                        ? scoreSubjects.get(condition.scoreId)
                        : condition.type === "members"
                          ? "group"
                          : conditionSubjects.get(condition.conditionIds[0]);
                if (subject !== undefined)
                    conditionSubjects.set(condition.id, subject);
            }
        }
        rule.conditions.forEach((condition, index) => {
            if (
                condition.type === "members" &&
                conditionSubjects.get(condition.conditionId) === "group"
            ) {
                issue(
                    ["conditions", index],
                    "A members condition must quantify a member condition",
                );
            } else if (
                condition.type !== "members" &&
                condition.type !== "comparison"
            ) {
                const subjects = new Set(
                    condition.conditionIds.map((id) =>
                        conditionSubjects.get(id),
                    ),
                );
                if (subjects.has("member") && subjects.has("group")) {
                    issue(
                        ["conditions", index],
                        "Quantify member conditions before combining them with group conditions",
                    );
                }
            }
        });
        for (const { comparison, scoreId, path } of comparisons) {
            if (
                comparison.type === "threshold" &&
                comparison.target.type === "personal"
            ) {
                if (scoreSubjects.get(scoreId) === "group")
                    issue(
                        path,
                        "A group score cannot use one member's personal target",
                    );
            }
        }
        if (rule.result.type === "ranking") {
            if (!scores.has(rule.result.scoreId))
                issue(["result", "scoreId"], "Unknown ranking score");
            if (scoreSubjects.get(rule.result.scoreId) === "group")
                issue(["result", "scoreId"], "A ranking needs member scores");
            if (
                rule.result.eligibilityConditionId !== null &&
                !conditions.has(rule.result.eligibilityConditionId)
            ) {
                issue(
                    ["result", "eligibilityConditionId"],
                    "Unknown eligibility condition",
                );
            }
            if (
                rule.result.eligibilityConditionId !== null &&
                conditionSubjects.get(rule.result.eligibilityConditionId) ===
                    "group"
            ) {
                issue(
                    ["result", "eligibilityConditionId"],
                    "Ranking eligibility needs a member condition",
                );
            }
            rule.result.zones.forEach((zone, index) => {
                if (zone.from > zone.to)
                    issue(
                        ["result", "zones", index],
                        "Rank bounds are reversed",
                    );
            });
        } else if (!conditions.has(rule.result.conditionId)) {
            issue(["result", "conditionId"], "Unknown goal condition");
        } else if (
            conditionSubjects.get(rule.result.conditionId) !==
            (rule.result.scope === "group" ? "group" : "member")
        ) {
            issue(
                ["result", "scope"],
                "Goal scope does not match its condition",
            );
        }

        const selections = [
            ...rule.stake.actions.flatMap((action) => [
                action.liable,
                action.beneficiaries,
            ]),
            ...(rule.stake.money === null
                ? []
                : [rule.stake.money.contributors]),
            ...(rule.allocation === null ? [] : [rule.allocation.recipients]),
        ];
        for (const selection of selections) {
            if (selection.type === "ranked" && rule.result.type !== "ranking")
                issue(["result"], "Rank selections require a ranking Result");
            if (selection.type === "outcome") {
                const goalOutcome =
                    selection.outcome === "success" ||
                    selection.outcome === "failure";
                if (goalOutcome !== (rule.result.type === "goal"))
                    issue(
                        ["result"],
                        "Selected outcome does not belong to this Result type",
                    );
            }
        }
        if ((rule.stake.money === null) !== (rule.allocation === null)) {
            issue(
                ["allocation"],
                "A money Stake and its Allocation must be defined together",
            );
        }
        if (rule.stake.money?.contribution.type === "per_score_unit") {
            const score = scores.get(rule.stake.money.contribution.scoreId);
            if (!score)
                issue(
                    ["stake", "money", "contribution", "scoreId"],
                    "Unknown contribution score",
                );
            else if (
                score.type !== "measured" ||
                score.subject !== "member" ||
                score.reduction.type !== "count_matching" ||
                score.buckets === "fight"
            ) {
                issue(
                    ["stake", "money", "contribution", "scoreId"],
                    "Variable contributions require a count of matching days or workouts per member",
                );
            }
        }
        if (rule.allocation?.method.type === "rank_weights") {
            if (rule.result.type !== "ranking")
                issue(
                    ["allocation", "method"],
                    "Rank weights require a ranking Result",
                );
            if (
                rule.allocation.method.basisPoints.reduce(
                    (total, value) => total + value,
                    0,
                ) !== 10_000
            ) {
                issue(
                    ["allocation", "method", "basisPoints"],
                    "Rank shares must total 10,000 basis points (100%)",
                );
            }
        }
        if (rule.allocation?.method.type === "score_weights") {
            const score = scores.get(rule.allocation.method.scoreId);
            if (!score)
                issue(
                    ["allocation", "method", "scoreId"],
                    "Unknown allocation score",
                );
            else if (score.type !== "measured" || score.subject !== "member") {
                issue(
                    ["allocation", "method", "scoreId"],
                    "Score weights require a non-derived member score",
                );
            }
        }
    });

export type FightRulesDraft = z.infer<typeof fightRulesDraftSchema>;
