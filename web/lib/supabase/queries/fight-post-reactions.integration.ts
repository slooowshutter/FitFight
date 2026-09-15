import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { listFightPostReactionPeople } from "./fight-post-engagement-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 1 });
after(() => database.end());

test("reaction people respect membership, blocks, deletion, and pagination", async (t) => {
    const users = Array.from({ length: 5 }, () => randomUUID());
    const [owner, accepted, deferred, invited, outsider] = users;
    const fightId = randomUUID();
    const postId = randomUUID();
    t.after(async () => {
        await database`delete from public.fights where id = ${fightId}`;
        await database`delete from auth.users where id in ${database(users)}`;
    });
    for (const user of users)
        await database`insert into auth.users (id) values (${user})`;
    await database`
        insert into public.fights (
            id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy
        ) values (
            ${fightId}, ${owner}, 'Reaction list', 'live', now(), now() + interval '7 days',
            'UTC', 'highest_total', 'shared'
        )
    `;
    await database`
        insert into public.fight_members (fight_id, user_id, state) values
            (${fightId}, ${owner}, 'accepted'),
            (${fightId}, ${accepted}, 'accepted'),
            (${fightId}, ${deferred}, 'deferred'),
            (${fightId}, ${invited}, 'invited')
    `;
    await database`
        insert into public.fight_posts (id, fight_id, audience, author_id, body)
        values (${postId}, ${fightId}, 'fight', ${owner}, 'A post with reactions')
    `;
    await database`
        insert into public.fight_post_reactions (post_id, user_id, emoji) values
            (${postId}, ${accepted}, '❤️'), (${postId}, ${deferred}, '🔥')
    `;

    const expected = [accepted, deferred].sort();
    for (const viewer of [owner, accepted, deferred]) {
        const first = await listFightPostReactionPeople(
            viewer,
            postId,
            { limit: 1 },
            database,
        );
        assert.equal(first.people[0].user_id, expected[0]);
        assert.equal(first.next_cursor, expected[0]);
        const second = await listFightPostReactionPeople(
            viewer,
            postId,
            { limit: 1, cursor: first.next_cursor },
            database,
        );
        assert.equal(second.people[0].user_id, expected[1]);
        assert.equal(second.next_cursor, null);
        assert.deepEqual(
            new Set([first.people[0].emoji, second.people[0].emoji]),
            new Set(["❤️", "🔥"]),
        );
    }
    for (const viewer of [invited, outsider]) {
        await assert.rejects(
            listFightPostReactionPeople(
                viewer,
                postId,
                { limit: 40 },
                database,
            ),
            { status: 403 },
        );
    }
    await assert.rejects(
        listFightPostReactionPeople(
            owner,
            randomUUID(),
            { limit: 40 },
            database,
        ),
        { status: 404 },
    );

    await database`insert into private.feed_blocks (blocker_id, blocked_id) values (${owner}, ${accepted})`;
    const filtered = await listFightPostReactionPeople(
        owner,
        postId,
        { limit: 1 },
        database,
    );
    assert.deepEqual(
        filtered.people.map((person) => person.user_id),
        [deferred],
    );
    assert.equal(filtered.next_cursor, null);

    await database`insert into private.feed_blocks (blocker_id, blocked_id) values (${accepted}, ${owner})`;
    assert.deepEqual(
        await listFightPostReactionPeople(
            accepted,
            postId,
            { limit: 40 },
            database,
        ),
        {
            people: [],
            next_cursor: null,
        },
    );
    await database`update public.profiles set deleted_at = now() where user_id = ${deferred}`;
    assert.deepEqual(
        await listFightPostReactionPeople(
            owner,
            postId,
            { limit: 40 },
            database,
        ),
        {
            people: [],
            next_cursor: null,
        },
    );
});
