import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import {
    createFeedPostsRequestSchema,
    fightPostListResponseSchema,
} from "@/lib/types/feed/fight-post";
import { createFeedPosts, getFightPost, listFightPosts } from "./fight-posts-supabase-query";
import { createFightPostComment } from "./fight-post-engagement-supabase-query";
import { changeFriendship } from "./profile-friends-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
process.env.NEXT_PUBLIC_SUPABASE_URL = env.SUPABASE_TEST_URL;
process.env.SUPABASE_SERVICE_ROLE_KEY = env.SUPABASE_TEST_SERVICE_KEY;
const database = postgres(env.DATABASE_URL, { max: 1 });
after(() => database.end());

test("friends posts reach friends on Feed and stay out of fights and other people's Feeds", async (t) => {
    const users = Array.from({ length: 4 }, () => randomUUID());
    const [author, friend, opponent, stranger] = users;
    const fightId = randomUUID();
    t.after(async () => {
        await database`delete from public.fights where id = ${fightId}`;
        // Accepting a friend starts a friend round, whose fights and series hold both accounts.
        await database`delete from public.fights where friends and owner_id in ${database(users)}`;
        await database`delete from public.fight_series where friend_low is not null and owner_id in ${database(users)}`;
        await database`delete from auth.users where id in ${database(users)}`;
    });
    for (const user of users) await database`insert into auth.users (id) values (${user})`;
    await database`
        insert into public.fights (id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy)
        values (${fightId}, ${author}, 'Office Showdown', 'live', now(), now() + interval '7 days', 'UTC', 'highest_total', 'shared')
    `;
    await database`
        insert into public.fight_members (fight_id, user_id, state) values
            (${fightId}, ${author}, 'accepted'), (${fightId}, ${opponent}, 'accepted')
    `;
    await changeFriendship(friend, author, "request", database);
    await changeFriendship(author, friend, "accept", database);

    const friendsOnly = (await createFeedPosts(author, createFeedPostsRequestSchema.parse({
        body: "Friends only",
        destinations: [{ type: "friends" }],
    }), database)).posts[0];
    const everyone = (await createFeedPosts(author, createFeedPostsRequestSchema.parse({
        body: "Friends and the office",
        destinations: [{ type: "friends" }, { type: "fight", fight_id: fightId }],
    }), database)).posts[0];
    assert.ok(friendsOnly && everyone);
    assert.equal(friendsOnly.to_friends, true);
    assert.equal(friendsOnly.audience, "main");
    assert.equal(friendsOnly.fight_id, null);
    assert.equal(everyone.audience, "fight");
    assert.equal(everyone.channels[0]?.fight_id, fightId);

    const feedIds = async (viewer: string) =>
        fightPostListResponseSchema.parse(await listFightPosts(viewer, undefined, { limit: 30 }, database))
            .posts.map((post) => post.id);
    assert.deepEqual(await feedIds(author), [everyone.id, friendsOnly.id]);
    assert.deepEqual(await feedIds(friend), [everyone.id, friendsOnly.id]);
    assert.deepEqual(await feedIds(opponent), [everyone.id]);
    assert.deepEqual(await feedIds(stranger), []);
    // Old builds asked for scope=all; the old Main rule must not leak a friends-only post.
    assert.deepEqual(
        (await listFightPosts(opponent, undefined, { limit: 30, scope: "all" }, database)).posts.map((post) => post.id),
        [everyone.id],
    );
    assert.deepEqual(
        (await listFightPosts(opponent, fightId, { limit: 30 }, database)).posts.map((post) => post.id),
        [everyone.id],
        "A fight's own Feed shows only posts made for that fight",
    );

    const asFriend = (await getFightPost(friend, everyone.id, database)).post;
    const listedForFriend = (await listFightPosts(friend, undefined, { limit: 30 }, database)).posts
        .find((post) => post.id === everyone.id);
    for (const post of [asFriend, listedForFriend]) {
        assert.ok(post);
        assert.deepEqual(
            [post.audience, post.fight_id, post.fight_name, post.channels, post.to_friends],
            ["main", null, "", [], true],
            "A friend outside the fight sees a friends-only post and learns nothing about the fight",
        );
    }
    const asOpponent = (await getFightPost(opponent, everyone.id, database)).post;
    assert.deepEqual([asOpponent.audience, asOpponent.fight_id], ["fight", fightId]);
    await createFightPostComment(friend, friendsOnly.id, { body: "Nice walk" }, database);
    for (const viewer of [opponent, stranger]) {
        await assert.rejects(getFightPost(viewer, friendsOnly.id, database), { status: 403 });
    }

    await changeFriendship(author, friend, "remove", database);
    assert.deepEqual(await feedIds(friend), [], "Removing a friend hides their friends posts");
});
