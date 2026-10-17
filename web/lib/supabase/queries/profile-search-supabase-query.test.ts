import assert from "node:assert/strict";
import { test } from "node:test";
import { GET as readSearch } from "@/app/api/v1/profiles/search/route";
import { profileSearchRequestSchema } from "@/lib/types/profiles/profile-search";
import { searchProfiles } from "./profile-search-supabase-query";

test("search matches username prefixes without the caller, deleted people, or blocks", async () => {
    const userId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    const rows = [
        {
            user_id: "33333333-3333-4333-8333-333333333333", handle: "fabi", display_name: "Fabi", companion_id: null,
            avatar_url: null, avatar_path: null,
        },
    ];
    let query = "";
    let values: unknown[] = [];
    const database = async (strings: TemplateStringsArray, ...parameters: unknown[]) => {
        query = strings.join("?");
        values = parameters;
        return rows;
    };
    const result = await searchProfiles(userId, "fab", database as never);
    assert.deepEqual(result, { people: rows.map(({ avatar_path: _path, ...person }) => person) });
    assert.ok(values.includes("fab") && values.includes(userId));
    assert.match(query, /starts_with\(lower\(profile.handle\), \?\)/, "underscores in usernames are not LIKE wildcards");
    assert.match(query, /profile.deleted_at is null/);
    assert.match(query, /private.profile_blocks/);
    assert.match(query, /order by lower\(profile.handle\) = \? desc/);
    assert.match(query, /limit 8/);
});

test("search input is normalized like a username and needs 2 characters", () => {
    assert.deepEqual(profileSearchRequestSchema.parse({ q: " @Fab_I " }), { q: "fab_i" });
    assert.equal(profileSearchRequestSchema.safeParse({ q: "f" }).success, false);
    assert.equal(profileSearchRequestSchema.safeParse({ q: "fa%" }).success, false);
});

test("the search endpoint authenticates before touching the database", async () => {
    const response = await readSearch(
        new Request("https://staging.fitfight.app/api/v1/profiles/search?q=fab"),
        { params: Promise.resolve({}) },
    );
    assert.equal(response.status, 401);
});
