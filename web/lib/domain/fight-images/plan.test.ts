import assert from "node:assert/strict";
import { test } from "node:test";
import { fightImageRunners, judgeFightImage, planFightImage } from "./plan";
import type { FightImageCastRow } from "@/lib/types/fight-images/fight-image";

function row(index: number, companion: string | null, extra: Partial<FightImageCastRow> = {}): FightImageCastRow {
    return {
        user_id: `00000000-0000-4000-8000-${String(index).padStart(12, "0")}`,
        is_owner: index === 0,
        accepted_at: new Date(Date.UTC(2026, 9, 16, 9, index)),
        companion_id: companion,
        companion_image_url: null,
        companion_prompt: null,
        ...extra,
    };
}

const customArt = "https://supabase.tryblend.ai/storage/v1/object/public/generated/a/custom.png";

test("a small fight draws everyone on the trail and counts duplicates", () => {
    const runners = fightImageRunners([row(0, "badger"), row(1, "badger"), row(2, "fox")], new Map());
    const plan = planFightImage(runners);
    assert.equal(plan.layout, "trail");
    assert.equal(plan.sheet.length, 3);
    assert.deepEqual(plan.expected, { Badger: 2, Fox: 1 });
    assert.match(plan.roster, /^Total characters: 3\nBadger \(x2\): A stocky badger/);
    assert.equal(plan.crowdSize, 0);
});

test("16 runners stay on the trail and 17 switch to a race start with 12 featured", () => {
    const sixteen = fightImageRunners(Array.from({ length: 16 }, (_, i) => row(i, "fox")), new Map());
    assert.equal(planFightImage(sixteen).layout, "trail");
    const seventeen = fightImageRunners(Array.from({ length: 17 }, (_, i) => row(i, "fox")), new Map());
    const plan = planFightImage(seventeen);
    assert.equal(plan.layout, "race_start");
    assert.equal(plan.sheet.length, 12);
    assert.equal(plan.crowdSize, 5);
    assert.equal(plan.crowdCompanions, "Fox x5");
    assert.match(plan.roster, /^Total characters: 12\n/);
});

test("a race start features the creator, then custom companions, then Specials, then join order", () => {
    const rows = [
        row(0, "badger"),
        ...Array.from({ length: 14 }, (_, i) => row(i + 1, "fox")),
        row(20, "limited-tiger"),
        row(21, "custom", { companion_image_url: customArt, companion_prompt: "A sleepy orangutan in a bandana" }),
    ];
    const plan = planFightImage(fightImageRunners(rows, new Map([[rows[16].user_id, "Ziggy"]])));
    assert.deepEqual(
        plan.sheet.slice(0, 3).map((runner) => runner.rosterName).sort(),
        ["Badger", "Tiger with red hand wraps", "Ziggy"].sort(),
    );
    assert.equal(plan.expected.Fox, 9);
    assert.equal(plan.crowdCompanions, "Fox x5");
});

test("a custom companion named like a built-in one gets its own caption", () => {
    const runners = fightImageRunners(
        [row(0, "fox"), row(1, "custom", { companion_image_url: customArt, companion_prompt: "A fox in a red bandana" })],
        new Map([[row(1, null).user_id, "Fox"]]),
    );
    assert.deepEqual(runners.map((runner) => runner.rosterName), ["Fox", "Fox 2"]);
    assert.equal(runners[1].artUrl, customArt);
    assert.equal(runners[1].description, "A fox in a red bandana");
});

test("a profile without a companion runs as the default Badger", () => {
    const [runner] = fightImageRunners([row(0, null)], new Map());
    assert.equal(runner.rosterName, "Badger");
    assert.equal(runner.kind, "stock");
});

test("the trail check needs exact counts, nothing extra and nobody facing left", () => {
    const expected = { Badger: 2, Fox: 1 };
    const ok = '```json\n{"total": 3, "counts": [{"name": "Badger", "count": 2}, {"name": "Fox (x1)", "count": 1}], "unknown": 0, "facing_left": 0}\n```';
    assert.deepEqual(judgeFightImage("trail", expected, ok), { pass: true, problems: [] });
    const missing = '{"total": 2, "counts": [{"name": "Badger", "count": 1}, {"name": "Fox", "count": 1}], "unknown": 0, "facing_left": 0}';
    assert.equal(judgeFightImage("trail", expected, missing).pass, false);
    const extra = '{"total": 4, "counts": [{"name": "Badger", "count": 2}, {"name": "Fox", "count": 1}, {"name": "Otter", "count": 1}], "unknown": 0, "facing_left": 0}';
    assert.equal(judgeFightImage("trail", expected, extra).pass, false);
    const left = '{"total": 3, "counts": [{"name": "Badger", "count": 2}, {"name": "Fox", "count": 1}], "unknown": 0, "facing_left": 1}';
    assert.deepEqual(judgeFightImage("trail", expected, left).problems, ["facing left: 1"]);
    assert.deepEqual(judgeFightImage("trail", expected, "not json").problems, ["unreadable check"]);
});

test("the race start check only needs every featured runner present and facing right", () => {
    const expected = { Badger: 1, Ziggy: 1 };
    const crowd = '{"total": 9, "counts": [{"name": "Badger", "count": 6}, {"name": "Ziggy", "count": 1}], "unknown": 0, "facing_left": 0, "crowd_estimate": 70}';
    assert.equal(judgeFightImage("race_start", expected, crowd).pass, true);
    const lost = '{"total": 6, "counts": [{"name": "Badger", "count": 6}], "unknown": 0, "facing_left": 0}';
    assert.deepEqual(judgeFightImage("race_start", expected, lost).problems, ["Ziggy: expected 1, saw 0"]);
});
