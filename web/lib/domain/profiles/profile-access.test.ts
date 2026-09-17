import assert from "node:assert/strict";
import { test } from "node:test";
import { profileAccess } from "./profile-access";
import { defaultProfileSettings } from "@/lib/types/profiles/shared-profile";

test("all four profile modes respect friend, current opponent, and stranger access", () => {
    for (const competitive of [false, true]) {
        for (const audience of ["private", "public"] as const) {
            for (const relation of ["owner", "friend", "current_opponent", "stranger"] as const) {
                const access = profileAccess({ ...defaultProfileSettings, competitive, audience }, {
                    owner: relation === "owner", friend: relation === "friend",
                    current_opponent: relation === "current_opponent", blocked: false,
                });
                assert.equal(access.identity, true);
                assert.equal(access.record, relation === "owner" || competitive && (audience === "public" || relation !== "stranger"));
                assert.equal(access.activity, relation === "owner");
            }
        }
    }
});

test("activity sharing has its own audience and requires a public profile for public history", () => {
    for (const audience of ["off", "friends", "opponents", "public"] as const) {
        const friend = { owner: false, friend: true, current_opponent: false, blocked: false };
        const opponent = { ...friend, friend: false, current_opponent: true };
        const stranger = { ...friend, friend: false };
        const settings = { ...defaultProfileSettings, activity_audience: audience };
        assert.equal(profileAccess(settings, friend).activity, audience === "friends" || audience === "opponents");
        assert.equal(profileAccess(settings, opponent).activity, audience === "opponents");
        assert.equal(profileAccess(settings, stranger).activity, false);
        assert.equal(profileAccess({ ...settings, audience: "public" }, stranger).activity, audience === "public");
    }
});

test("blocking overrides every profile mode and relationship", () => {
    assert.deepEqual(profileAccess({ ...defaultProfileSettings, competitive: true, audience: "public", activity_audience: "public" }, {
        owner: false, friend: true, current_opponent: true, blocked: true,
    }), { identity: false, shared: false, record: false, activity: false });
});
