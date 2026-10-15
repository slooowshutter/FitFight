import assert from "node:assert/strict";
import { test } from "node:test";
import type { Sql } from "postgres";
import { defaultNotificationPreferences } from "@/lib/types/notifications/notification-preferences";
import { processNotificationOutbox } from "./process-notification-outbox-supabase-query";

test("friend rounds drop per-fight pushes at send time and gate their batched pushes by the existing controls", async () => {
    delete process.env.APNS_KEY_ID;
    delete process.env.APNS_PRIVATE_KEY;
    delete process.env.APNS_TOKEN_ENCRYPTION_KEY;
    const userId = "a0000000-0000-4000-8000-000000000000";
    const friendRound = "b0000000-0000-4000-8000-000000000000";
    const normalFight = "b0000000-0000-4000-8000-000000000001";
    const base = {
        user_id: userId,
        fight_id: friendRound,
        slot: "t0",
        route: `/fights/${friendRound}?friends=1`,
        alert_body: null,
        expires_at: "2026-11-02T00:00:00Z",
        fight_state: "awaiting_final_sync",
        fight_host_id: null,
        fight_friends: true,
        fight_name: "Friends",
        owner_handle: "owner",
        ends_at: "2026-11-01T00:00:00Z",
        sync_deadline: "2026-11-02T00:00:00Z",
        time_zone: "UTC",
        member_state: "accepted",
        final_steps_complete: false,
        preferences: defaultNotificationPreferences,
    };
    const perFightKinds = ["fight_ended", "final_sync", "ending_24h", "ending_week", "fight_finalized", "daily_status"];
    const rows = [
        ...perFightKinds.map((kind, index) => ({
            ...base,
            id: `c0000000-0000-4000-8000-00000000000${index}`,
            kind,
            copy_key: kind === "fight_ended" ? "fight_ended_everyone" : kind,
        })),
        { ...base, id: "d0000000-0000-4000-8000-000000000000", kind: "friends_sync", copy_key: "friends_sync" },
        {
            ...base,
            id: "d0000000-0000-4000-8000-000000000001",
            kind: "friends_sync",
            copy_key: "friends_sync",
            preferences: { ...defaultNotificationPreferences, final_sync: false },
        },
        {
            ...base,
            id: "d0000000-0000-4000-8000-000000000002",
            kind: "friends_sync",
            copy_key: "friends_sync",
            final_steps_complete: true,
        },
        {
            ...base,
            id: "d0000000-0000-4000-8000-000000000003",
            kind: "friends_results",
            copy_key: "friends_results",
            slot: "final",
            fight_state: "final",
            final_steps_complete: true,
        },
        {
            ...base,
            id: "d0000000-0000-4000-8000-000000000004",
            kind: "friends_results",
            copy_key: "friends_results",
            slot: "final",
            fight_state: "final",
            preferences: { ...defaultNotificationPreferences, fight_finalized: false },
        },
        {
            ...base,
            id: "e0000000-0000-4000-8000-000000000000",
            fight_id: normalFight,
            fight_friends: false,
            kind: "fight_finalized",
            copy_key: "fight_finalized",
            slot: "final",
            fight_state: "final",
            route: `/fights/${normalFight}`,
        },
    ];
    const marks = new Map<string, readonly unknown[]>();
    const database = ((strings: TemplateStringsArray, ...values: unknown[]) => {
        const query = strings.join("?");
        if (query.includes("with picked")) return Promise.resolve(rows);
        if (query.includes("where id = ")) marks.set(String(values[2]), values.slice(0, 2));
        return Promise.resolve([]);
    }) as unknown as Sql;

    const result = await processNotificationOutbox(new Date("2026-11-01T00:05:00Z"), database);

    for (let index = 0; index < perFightKinds.length; index += 1) {
        assert.deepEqual(marks.get(`c0000000-0000-4000-8000-00000000000${index}`), ["skipped", "superseded"], perFightKinds[index]);
    }
    assert.equal(marks.has("d0000000-0000-4000-8000-000000000000"), false, "friends_sync goes out by default");
    assert.deepEqual(marks.get("d0000000-0000-4000-8000-000000000001"), ["skipped", "muted"]);
    assert.deepEqual(marks.get("d0000000-0000-4000-8000-000000000002"), ["skipped", "already_complete"]);
    assert.equal(marks.has("d0000000-0000-4000-8000-000000000003"), false, "friends_results goes out by default");
    assert.deepEqual(marks.get("d0000000-0000-4000-8000-000000000004"), ["skipped", "muted"]);
    assert.equal(marks.has("e0000000-0000-4000-8000-000000000000"), false, "other fights keep their pushes");
    assert.equal(result.pending, 3);
});
