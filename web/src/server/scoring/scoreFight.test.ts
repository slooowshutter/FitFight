import assert from "node:assert/strict";
import { test } from "node:test";
import { competitionRank, fightPot, scoreFight } from "./scoreFight";

test("fight pot is stake times accepted count", () => {
  assert.equal(fightPot(1000, 3), 3000);
  assert.equal(fightPot(null, 3), 0);
  assert.equal(fightPot(500, 0), 0);
});

test("highest_total ranks by value and gives the pot to the winner", () => {
  const result = scoreFight({
    outcomeRule: "highest_total",
    stakeMinor: 1000,
    defaultGoalValue: null,
    members: [
      { userId: "b", value: 8000, personalTarget: null },
      { userId: "a", value: 12000, personalTarget: null },
      { userId: "c", value: 8000, personalTarget: null },
    ],
  });
  assert.deepEqual(
    result.map((row) => ({ userId: row.userId, rank: row.rank, outcomeMinor: row.outcomeMinor })),
    [
      { userId: "a", rank: 1, outcomeMinor: 3000 },
      { userId: "b", rank: 2, outcomeMinor: 0 },
      { userId: "c", rank: 2, outcomeMinor: 0 },
    ],
  );
});

test("highest_total ties split the pot evenly with deterministic remainder", () => {
  const result = scoreFight({
    outcomeRule: "highest_total",
    stakeMinor: 333,
    defaultGoalValue: null,
    members: [
      { userId: "c", value: 10, personalTarget: null },
      { userId: "a", value: 10, personalTarget: null },
      { userId: "b", value: 10, personalTarget: null },
    ],
  });
  const pot = 333 * 3;
  const amounts = result.map((row) => row.outcomeMinor);
  assert.equal(amounts.reduce((sum, n) => sum + n, 0), pot);
  assert.ok(amounts.every((n) => n === 333 || n === 334));
  assert.equal(result.find((row) => row.userId === "a")?.outcomeMinor, 333);
  assert.equal(competitionRank(10, [10, 10, 10]), 1);
});

test("proportional allocates share of pot and handles zero total", () => {
  const split = scoreFight({
    outcomeRule: "proportional",
    stakeMinor: 100,
    defaultGoalValue: null,
    members: [
      { userId: "a", value: 2, personalTarget: null },
      { userId: "b", value: 1, personalTarget: null },
    ],
  });
  assert.equal(split.find((row) => row.userId === "a")?.outcomeMinor, 133);
  assert.equal(split.find((row) => row.userId === "b")?.outcomeMinor, 67);

  const zero = scoreFight({
    outcomeRule: "proportional",
    stakeMinor: 100,
    defaultGoalValue: null,
    members: [
      { userId: "a", value: 0, personalTarget: null },
      { userId: "b", value: 0, personalTarget: null },
    ],
  });
  assert.ok(zero.every((row) => row.outcomeMinor === 0));
});

test("hit_your_goal sends the pot to members who hit personal or default target", () => {
  const oneHit = scoreFight({
    outcomeRule: "hit_your_goal",
    stakeMinor: 1000,
    defaultGoalValue: 8000,
    members: [
      { userId: "a", value: 9000, personalTarget: 8000 },
      { userId: "b", value: 5000, personalTarget: null },
    ],
  });
  assert.equal(oneHit.find((row) => row.userId === "a")?.outcomeMinor, 2000);
  assert.equal(oneHit.find((row) => row.userId === "a")?.hitGoal, true);
  assert.equal(oneHit.find((row) => row.userId === "b")?.outcomeMinor, 0);
  assert.equal(oneHit.find((row) => row.userId === "b")?.hitGoal, false);

  const none = scoreFight({
    outcomeRule: "hit_your_goal",
    stakeMinor: 500,
    defaultGoalValue: 10000,
    members: [
      { userId: "a", value: 100, personalTarget: null },
      { userId: "b", value: 200, personalTarget: 500 },
    ],
  });
  assert.ok(none.every((row) => row.outcomeMinor === 0));
});
