import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { recentSyncsSchema } from "@/lib/types/admin/recent-syncs";

test("the recent syncs response matches its contract fixture", () => {
    const fixture = JSON.parse(
        readFileSync(
            new URL(
                "../../../../contracts/fixtures/admin-recent-syncs.json",
                import.meta.url,
            ),
            "utf8",
        ),
    );
    const parsed = recentSyncsSchema.parse(fixture);
    assert.deepEqual(
        parsed.people.map((person) => [person.handle, person.last_synced_at]),
        [
            ["marc", "2026-10-12T09:15:00Z"],
            ["lea", "2026-10-08T21:40:00Z"],
        ],
    );
    assert.equal(
        recentSyncsSchema.safeParse({
            people: [{ ...fixture.people[0], last_synced_at: null }],
        }).success,
        false,
        "everyone listed has synced",
    );
});
