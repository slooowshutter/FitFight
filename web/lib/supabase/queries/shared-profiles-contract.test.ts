import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import { GET as readProfile } from "@/app/api/v1/profiles/[userID]/route";
import { POST as recordView } from "@/app/api/v1/profiles/[userID]/views/route";
import { POST as requestFriend } from "@/app/api/v1/friends/[userID]/request/route";
import { sharedProfileSchema, profileViewRequestSchema, updateProfileSettingsSchema } from "@/lib/types/profiles/shared-profile";
import { profileHistoryPageSchema } from "@/lib/types/profiles/profile-results";
import type { Sql } from "postgres";
import { readSharedProfile } from "./shared-profiles-supabase-query";

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

test("a custom companion's name and line reach only the owner and viewers the profile is shared with", async () => {
    const viewerID = "22222222-2222-4222-8222-222222222222";
    for (const [viewer, audience, visible] of [
        [userID, "private", true],
        [viewerID, "public", true],
        [viewerID, "private", false],
    ] as const) {
        const queries: string[] = [];
        const sql = ((strings: TemplateStringsArray) => {
            const text = strings.join("?").replace(/\s+/g, " ").trim();
            queries.push(text);
            if (text.startsWith("select id as user_id from public.profiles"))
                return Promise.resolve(viewer === userID ? [{ user_id: userID }] : [{ user_id: userID }, { user_id: viewerID }]);
            if (text.includes("'display_name', profile.display_name"))
                return Promise.resolve([{
                    time_zone: "UTC",
                    identity: { user_id: userID, handle: "max", display_name: "Max", companion_id: "custom" },
                    avatar_path: null,
                    companion_image_url: "https://cdn.tryblend.ai/max.png",
                    settings: {
                        competitive: false, audience, activity_audience: "off", activity_days: 7, artwork_allowed: false, revision: 0,
                    },
                    relationship: { owner: viewer === userID, friend: false, current_opponent: false, blocked: false },
                    friendship: viewer === userID ? "self" : "none",
                }]);
            if (text.includes("::date::text today")) return Promise.resolve([{ today: "2026-10-15", time_zone: "UTC" }]);
            if (text.includes("member_since")) return Promise.resolve([{ member_since: "2026-09-01", friends_since: null }]);
            if (text.includes("as companion_name"))
                return Promise.resolve([{ companion_name: "Max", companion_line: "Walks like rent is due." }]);
            return Promise.resolve([]);
        }) as unknown as Sql;
        Object.assign(sql, {
            begin: async (callback: (transaction: Sql) => Promise<unknown>) => callback(sql),
            json: (value: unknown) => value,
            array: (value: unknown) => value,
        });
        const profile = await readSharedProfile(viewer, userID, undefined, sql);
        assert.equal(profile.companion_name, visible ? "Max" : undefined, `${viewer} ${audience}`);
        assert.equal(profile.companion_line, visible ? "Walks like rent is due." : undefined);
        assert.equal(queries.some((query) => query.includes("as companion_name")), visible);
    }
});
