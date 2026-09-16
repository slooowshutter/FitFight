import assert from "node:assert/strict";
import { test } from "node:test";
import { classifyFightResult, profileRecord, rivalryRecord } from "./profile-results";
import { fightRecordFactSchema } from "@/lib/types/profiles/profile-results";

const first = "00000000-0000-4000-8000-000000000001";
const second = "00000000-0000-4000-8000-000000000002";
const fight = fightRecordFactSchema.parse({
    id: "00000000-0000-4000-8000-000000000003", state: "final",
    starts_at: "2026-09-10T00:00:00Z", ends_at: "2026-09-13T00:00:00Z", category: "unknown",
    name: "Private title", action_text: "Make coffee", outcome_rule: "highest_total",
    members: [first, second].map((user_id, index) => ({
        user_id, entered_at: "2026-09-10T00:00:00Z", departed_at: null, departure: null,
        state: "accepted", rank: index + 1, final_value: 1000 - index, complete: true,
        finalized_at: "2026-09-13T00:01:00Z", reliable: true,
    })),
});

test("10 played and 3 wins is 30 percent; categories do not change the denominator", () => {
    const results = Array.from({ length: 10 }, (_, index) => ({ ...fight, members: fight.members.map((member) => ({
        ...member, rank: index < 3 ? member.rank : member.rank === 1 ? 2 : 1,
    })) }));
    assert.equal(profileRecord(results, first).played, 10);
    assert.equal(profileRecord(results, first).wins, 3);
    assert.equal(profileRecord(results, first).win_rate, 0.3);
    assert.equal(profileRecord(results, first).categories.unknown.played, 10);
    assert.equal(profileRecord([], first).win_rate, null);
});

test("shared first and no complete final data award no wins", () => {
    for (const complete of [false, true]) {
        const tied = { ...fight, members: fight.members.map((member) => ({ ...member, rank: 1, complete })) };
        assert.equal(classifyFightResult(tied, first).result, "draw");
        assert.equal(profileRecord([tied], first).wins, 0);
        assert.equal(rivalryRecord([tied], first, second).draws, 1);
    }
});

test("a missing final sync preserves the actual forfeit without calling it quitting", () => {
    const partial = { ...fight, members: [fight.members[0], { ...fight.members[1], complete: false }] };
    assert.equal(classifyFightResult(partial, first).result, "win");
    assert.equal(classifyFightResult(partial, second).result, "incomplete");
    assert.equal(rivalryRecord([partial], second, first).losses, 1);
});

test("withdrawals after starting remain in the denominator; pre-start withdrawals and removal do not", () => {
    for (const departure of ["voluntary", "removed", "unknown"] as const) {
        const left = { ...fight, members: [{ ...fight.members[0], departure, departed_at: "2026-09-11T00:00:00Z", finalized_at: null, state: "withdrawn" }, fight.members[1]] };
        assert.equal(classifyFightResult(left, first).counted, departure === "voluntary");
        if (departure === "voluntary") {
            assert.equal(classifyFightResult(left, first).result, "withdrawn");
            assert.equal(classifyFightResult({ ...left, members: [{ ...left.members[0], departed_at: "2026-09-09T23:00:00Z" }, fight.members[1]] }, first).counted, false);
        }
    }
});

test("cancelled, ongoing, solo, unclassifiable and unentered history cannot award wins", () => {
    for (const excluded of [
        { ...fight, state: "cancelled" }, { ...fight, state: "live" },
        { ...fight, members: [fight.members[0]] },
        { ...fight, members: [{ ...fight.members[0], reliable: false }, fight.members[1]] },
        { ...fight, members: [{ ...fight.members[0], entered_at: null, state: "deferred" }, fight.members[1]] },
    ]) {
        assert.equal(classifyFightResult(excluded, first).counted, false);
        assert.equal(profileRecord([excluded], first).wins, 0);
    }
});

test("removal does not turn a group into a duel", () => {
    const group = { ...fight, members: [...fight.members, {
        ...fight.members[1], user_id: "00000000-0000-4000-8000-000000000004",
        departed_at: "2026-09-11T00:00:00Z", departure: "removed" as const,
    }] };
    assert.equal(classifyFightResult(group, first).fieldSize, 3);
    assert.deepEqual(rivalryRecord([group], first, second), { wins: 0, losses: 0, draws: 0, rematch: null });
});
