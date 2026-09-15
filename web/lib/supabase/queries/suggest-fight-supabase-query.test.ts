import assert from "node:assert/strict";
import { test } from "node:test";
import { PATCH as suggestFight } from "@/app/api/v1/fights/[fightID]/suggested/route";
import { GET as listSuggested } from "@/app/api/v1/fights/suggested/route";
import { suggestFightRequestSchema } from "@/lib/types/fights/suggest-fight";

const fightId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";

test("suggest fight is a boolean flag and rejects extra fields", () => {
    assert.deepEqual(suggestFightRequestSchema.parse({ suggested: true }), {
        suggested: true,
    });
    assert.deepEqual(suggestFightRequestSchema.parse({ suggested: false }), {
        suggested: false,
    });
    assert.equal(suggestFightRequestSchema.safeParse({}).success, false);
    assert.equal(
        suggestFightRequestSchema.safeParse({ suggested: true, extra: 1 })
            .success,
        false,
    );
});

test("suggest fight routes authenticate before reading or writing", async () => {
    const context = { params: Promise.resolve({ fightID: fightId }) };
    const listed = await listSuggested(
        new Request("https://staging.fitfight.app/api/v1/fights/suggested"),
        {
            params: Promise.resolve({}),
        },
    );
    const updated = await suggestFight(
        new Request(
            `https://staging.fitfight.app/api/v1/fights/${fightId}/suggested`,
            {
                method: "PATCH",
                headers: { "content-type": "application/json" },
                body: JSON.stringify({ suggested: true }),
            },
        ),
        context,
    );
    assert.equal(listed.status, 401);
    assert.equal(updated.status, 401);
});
