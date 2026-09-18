import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import { GET as readProfile } from "@/app/api/v1/profiles/[userID]/route";
import { POST as recordView } from "@/app/api/v1/profiles/[userID]/views/route";
import { POST as requestFriend } from "@/app/api/v1/friends/[userID]/request/route";
import { sharedProfileSchema, profileViewRequestSchema, updateProfileSettingsSchema } from "@/lib/types/profiles/shared-profile";
import { profileHistoryPageSchema } from "@/lib/types/profiles/profile-results";

const userID = "11111111-1111-4111-8111-111111111111";

test("new profile fixtures retain explicit hidden content and redacted Fight details", async () => {
    for (const name of ["shared-profile", "shared-profile-private", "shared-profile-statistics"]) {
        const fixture = JSON.parse(await readFile(`../contracts/fixtures/${name}.json`, "utf8"));
        assert.deepEqual(sharedProfileSchema.parse(fixture), fixture);
    }
    const history = JSON.parse(await readFile("../contracts/fixtures/profile-history.json", "utf8"));
    const parsed = profileHistoryPageSchema.parse(history);
    assert.equal(parsed.results[0].fight_id, null);
    assert.equal(parsed.results[0].name, null);
    assert.equal(parsed.results[0].field_size, 400);
});

test("profile commands reject spoofed actors, counters, invalid audiences and empty updates", () => {
    assert.equal(profileViewRequestSchema.safeParse({ event_id: userID, source: "friends", actor_id: userID }).success, false);
    assert.equal(profileViewRequestSchema.safeParse({ event_id: userID, source: "prefetch" }).success, false);
    assert.equal(updateProfileSettingsSchema.safeParse({}).success, false);
    assert.equal(updateProfileSettingsSchema.safeParse({ activity_days: 365 }).success, false);
    assert.equal(updateProfileSettingsSchema.safeParse({ user_id: userID, competitive: true }).success, false);
});

test("profile and friend endpoints authenticate before reading IDs or touching the database", async () => {
    const context = { params: Promise.resolve({ userID }) };
    const responses = await Promise.all([
        readProfile(new Request(`https://staging.fitfight.app/api/v1/profiles/${userID}`), context),
        recordView(new Request(`https://staging.fitfight.app/api/v1/profiles/${userID}/views`, { method: "POST" }), context),
        requestFriend(new Request(`https://staging.fitfight.app/api/v1/friends/${userID}/request`, { method: "POST" }), context),
    ]);
    for (const response of responses) {
        assert.equal(response.status, 401);
        assert.equal(response.headers.get("cache-control"), "no-store");
    }
});
