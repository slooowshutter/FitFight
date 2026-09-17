import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { listFightPostComments } from "./fight-post-engagement-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 1 });
after(() => database.end());

test("most comments pagination preserves subsecond ordering and UUID ties", async (t) => {
    const userId = randomUUID();
    const postId = randomUUID();
    const [firstId, secondId, thirdId] = Array.from({ length: 3 }, () =>
        randomUUID(),
    ).sort();
    t.after(async () => {
        await database`delete from public.fight_posts where id = ${postId}`;
        await database`delete from auth.users where id = ${userId}`;
    });
    await database`insert into auth.users (id) values (${userId})`;
    await database`
        insert into public.fight_posts (id, audience, author_id, body)
        values (${postId}, 'main', ${userId}, 'Comment pagination')
    `;
    await database`
        insert into public.fight_post_comments (id, post_id, author_id, body, created_at) values
            (${firstId}, ${postId}, ${userId}, 'Newer, lower UUID', '2026-09-17T12:00:00.900Z'),
            (${secondId}, ${postId}, ${userId}, 'Newer, higher UUID', '2026-09-17T12:00:00.900Z'),
            (${thirdId}, ${postId}, ${userId}, 'Older, highest UUID', '2026-09-17T12:00:00.100Z')
    `;
    for (const limit of [1, 2]) {
        const seen: string[] = [];
        let cursor: string | undefined;
        do {
            const page = await listFightPostComments(
                userId,
                postId,
                { sort: "comments", limit, cursor },
                database,
            );
            seen.push(...page.comments.map((comment) => comment.id));
            assert.ok(
                seen.length <= 3,
                "Pagination must not duplicate or loop over roots",
            );
            cursor = page.next_cursor ?? undefined;
        } while (cursor);
        assert.deepEqual(seen, [secondId, firstId, thirdId]);
    }
});
