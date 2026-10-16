import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import { GET as readSuggestions } from "@/app/api/v1/friends/suggestions/route";
import { friendSuggestionsSchema } from "@/lib/types/friends/friend-suggestion";
import { listFriendSuggestions } from "./friend-suggestions-supabase-query";

test("the friend suggestions fixture matches the API contract", async () => {
    const fixture = JSON.parse(await readFile("../contracts/fixtures/friend-suggestions.json", "utf8"));
    assert.deepEqual(friendSuggestionsSchema.parse(fixture), fixture);
    assert.equal(friendSuggestionsSchema.safeParse({ people: [{ ...fixture.people[0], shared_fights: 0 }] }).success, false);
});

test("suggestions return identities with their shared Fight count and never the storage path", async () => {
    const userId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    const rows = [
        {
            user_id: "33333333-3333-4333-8333-333333333333", handle: "maya", display_name: "Maya", companion_id: "custom",
            avatar_url: "https://cdn.tryblend.ai/maya.png", avatar_path: null, shared_fights: 3,
        },
        {
            user_id: "55555555-5555-4555-8555-555555555555", handle: "leo", display_name: "Leo", companion_id: null,
            avatar_url: null, avatar_path: null, shared_fights: 1,
        },
    ];
    let query = "";
    let values: unknown[] = [];
    const database = async (strings: TemplateStringsArray, ...parameters: unknown[]) => {
        query = strings.join("?");
        values = parameters;
        assert.ok(parameters.includes(userId));
        return rows;
    };
    const result = await listFriendSuggestions(userId, database as never);
    assert.deepEqual(result, {
        people: rows.map(({ avatar_path: _path, ...person }) => person),
    });
    assert.match(query, /fight.host_id is null and not fight.friends/);
    assert.ok(values.includes("PGG7"), "the app-wide Fight never makes people suggestions");
    assert.match(query, /not coalesce\(series.suggested, false\)/);
    assert.match(query, /my_series.state in \('accepted', 'deferred'\) and their_series.state in \('accepted', 'deferred'\)/);
    assert.match(query, /private.profile_friendships/);
    assert.match(query, /private.feedback_blocks/);
    assert.match(query, /order by shared.shared_fights desc, shared.last_shared_at desc/);
    assert.match(query, /limit 10/);
});

test("the suggestions endpoint authenticates before touching the database", async () => {
    const response = await readSuggestions(
        new Request("https://staging.fitfight.app/api/v1/friends/suggestions"),
        { params: Promise.resolve({}) },
    );
    assert.equal(response.status, 401);
    assert.equal(response.headers.get("cache-control"), "no-store");
});
