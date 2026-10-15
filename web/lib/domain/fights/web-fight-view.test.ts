import assert from "node:assert/strict";
import { test } from "node:test";
import type { FightSnapshot } from "@/lib/types/fights/fight-snapshot";
import { webFights } from "./web-fight-view";

const you = "00000000-0000-4000-8000-000000000001";
const rival = "00000000-0000-4000-8000-000000000002";
const invitee = "00000000-0000-4000-8000-000000000003";

function snapshot(
    state: FightSnapshot["fights"][number]["state"],
    yourState: "accepted" | "invited" | "declined",
) {
    const fight = {
        id: "10000000-0000-4000-8000-000000000001",
        owner_id: rival,
        name: "Office",
        state,
        starts_at: "2026-10-01T00:00:00Z",
        ends_at: "2026-10-08T00:00:00Z",
        grace_ends_at: "2026-10-09T00:00:00Z",
        action_text: null,
        series_id: null,
    };
    const member = (
        user_id: string,
        memberState: "accepted" | "invited" | "declined",
        steps: number | null,
    ) => ({
        fight_id: fight.id,
        user_id,
        state: memberState,
        current_value: steps,
        rank: null,
        final_value: null,
        last_synced_at: null,
        final_steps_complete: false,
    });
    const profile = (user_id: string, handle: string) => ({
        user_id,
        handle,
        display_name: handle,
        avatar: null,
        companion_id: null,
    });
    return {
        fights: [fight],
        members: [
            member(invitee, "invited", null),
            member(you, yourState, 4000),
            member(rival, "accepted", 9000),
        ],
        profiles: [
            profile(you, "you"),
            profile(rival, "rival"),
            profile(invitee, "invitee"),
        ],
        series: [],
        step_days: [],
        hosted: null,
    } satisfies FightSnapshot;
}

test("webFights buckets like the app and ranks players before invitees", () => {
    const before = new Date("2026-10-05T00:00:00Z");
    const after = new Date("2026-10-08T12:00:00Z");

    const [live] = webFights(snapshot("live", "accepted"), you, before);
    assert.equal(live.status, "live");
    assert.deepEqual(
        live.standings.map((standing) => [
            standing.profile.handle,
            standing.steps,
            standing.you,
        ]),
        [
            ["rival", 9000, false],
            ["you", 4000, true],
            ["invitee", 0, false],
        ],
    );

    assert.equal(
        webFights(snapshot("live", "accepted"), you, after)[0].status,
        "pending",
    );
    assert.equal(
        webFights(snapshot("live", "invited"), you, before)[0].status,
        "invited",
    );
    assert.equal(
        webFights(snapshot("final", "invited"), you, before)[0].status,
        "finished",
    );
    assert.equal(
        webFights(snapshot("live", "declined"), you, before).length,
        0,
    );
    assert.equal(
        webFights(snapshot("draft", "accepted"), you, before).length,
        0,
    );
});
