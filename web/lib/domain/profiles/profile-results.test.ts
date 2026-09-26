import assert from "node:assert/strict";
import { test } from "node:test";
import { classifyFightResult, profileRecord, rivalryRecord } from "./profile-results";
import { fightRecordFactSchema } from "@/lib/types/profiles/profile-results";

const first = "00000000-0000-4000-8000-000000000001";
const second = "00000000-0000-4000-8000-000000000002";
const fight = fightRecordFactSchema.parse({
    history_id: "00000000-0000-4000-8000-000000000005",
    summary: null,
    id: "00000000-0000-4000-8000-000000000003", state: "final",
    calendar_days: 3,
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
        assert.equal(rivalryRecord([tied], first, second, new Set([fight.id])).draws, 1);
    }
});

test("a missing final sync preserves the actual forfeit without calling it quitting", () => {
    const partial = { ...fight, members: [fight.members[0], { ...fight.members[1], complete: false }] };
    assert.equal(classifyFightResult(partial, first).result, "win");
    assert.equal(classifyFightResult(partial, second).result, "incomplete");
    assert.equal(rivalryRecord([partial], second, first, new Set([fight.id])).losses, 1);
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
    assert.deepEqual(rivalryRecord([group], first, second, new Set([fight.id])), { wins: 0, losses: 0, draws: 0, rematch: null });
});

test("historical rivalry scores cannot expose rematch details after either person leaves", () => {
    assert.deepEqual(rivalryRecord([fight], first, second, new Set()), { wins: 1, losses: 0, draws: 0, rematch: null });
});

test("a rivalry scores the same from either person's recorded Fights", () => {
    const third = "00000000-0000-4000-8000-000000000006";
    const [recent, older, firstOnly, secondOnly] = [10, 11, 12, 13].map((n) => `00000000-0000-4000-8000-0000000000${n}`);
    const record = (id: string, historyId: number, members: typeof fight.members) => ({
        ...fight, id, history_id: `00000000-0000-4000-8000-0000000000${historyId}`, members,
    });
    const loss = fight.members.map((member) => ({ ...member, rank: member.rank === 1 ? 2 : 1 }));
    const withThird = (index: number) => [fight.members[index], { ...fight.members[1 - index], user_id: third }];
    // Each person's history IDs differ, and each also has a duel the other never joined.
    const firstFacts = [record(recent, 20, fight.members), record(firstOnly, 21, withThird(0)), record(older, 22, loss)];
    const secondFacts = [record(recent, 30, fight.members), record(older, 31, loss), record(secondOnly, 32, withThird(1))];
    for (const shared of [new Set<string>(), new Set([older]), new Set([recent, older])]) {
        assert.deepEqual(rivalryRecord(firstFacts, first, second, shared), rivalryRecord(secondFacts, first, second, shared));
    }
    assert.deepEqual(rivalryRecord(firstFacts, first, second, new Set([recent, older])), {
        wins: 1, losses: 1, draws: 0, rematch: { duration_seconds: 3 * 86400, duration_days: 3, action_text: "Make coffee" },
    });
});
