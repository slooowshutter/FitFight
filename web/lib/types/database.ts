import type {
    fightMemberStateValues,
    fightStateValues,
} from "@/lib/types/fights/membership-decision";

export type FightState = (typeof fightStateValues)[number];

export type FightMemberState = (typeof fightMemberStateValues)[number];

export type OutcomeRule = "highest_total" | "proportional" | "hit_your_goal";

export type GoalPolicy = "shared" | "personal" | "recommended_personal";

export type StakeKind = "bragging" | "money" | "action";

export type FightRow = {
    id: string;
    owner_id: string;
    name: string;
    state: FightState;
    starts_at: string;
    ends_at: string;
    time_zone: string;
    metric: string;
    metric_definition_version: number;
    outcome_rule: OutcomeRule;
    goal_policy: GoalPolicy;
    default_goal_value: number | string | null;
    tie_rule: string;
    stake_kind: StakeKind;
    stake_minor: number | null;
    currency: string | null;
    action_text: string | null;
    rules_version: number;
    scoring_engine_version: number;
    final_sync_grace_seconds: number;
    created_at: string;
    series_id: string | null;
};

export type FightMemberRow = {
    fight_id: string;
    user_id: string;
    state: FightMemberState;
    accepted_at: string | null;
    selected_source_id: string | null;
    source_label: string | null;
    personal_target: number | string | null;
    target_origin: string | null;
    target_formula_version: number | null;
    acceptance_copy_version: number | null;
    current_value: number | string | null;
    rank: number | null;
    outcome_minor: number | null;
    freshness: string | null;
    input_revision: number | null;
    last_synced_at: string | null;
    final_steps_complete: boolean;
    final_value: number | string | null;
    finalized_at: string | null;
};

export type DataSourceRow = {
    id: string;
    user_id: string;
    provider: string;
    source_label: string;
    contributing_source_labels: string[];
    connection_route: string;
    status: string;
    complete_through: string | null;
};

export type ProfileRow = {
    user_id: string;
    handle: string;
    display_name: string;
    time_zone: string | null;
};

export type FightSeriesRow = {
    id: string;
    owner_id: string;
    join_code: string | null;
    visibility: "invite_only" | "joinable";
    recurring: boolean;
    duration_seconds: number;
    name: string;
    action_text: string | null;
    time_zone: string;
    paused_at: string | null;
    current_fight_id: string | null;
    created_at: string;
    suggested: boolean;
    suggested_at: string | null;
};

export function asNumber(
    value: number | string | null | undefined,
): number | null {
    if (value === null || value === undefined) {
        return null;
    }
    const n = typeof value === "number" ? value : Number(value);
    return Number.isFinite(n) ? n : null;
}
