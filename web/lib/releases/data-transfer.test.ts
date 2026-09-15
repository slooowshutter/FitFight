import assert from "node:assert/strict";
import test from "node:test";
import { planDataTransfer, transferDigest } from "@/lib/releases/data-transfer";
import {
    transferSnapshotSchema,
    transferRequestSchema,
    transferTableValues,
    type TransferRow,
} from "@/lib/types/releases/data-transfer";

function transferFixtures() {
    const ids = {
        beta: "10000000-0000-4000-8000-000000000001",
        added: "10000000-0000-4000-8000-000000000002",
        prod: "10000000-0000-4000-8000-000000000003",
        betaIdentity: "20000000-0000-4000-8000-000000000001",
        addedIdentity: "20000000-0000-4000-8000-000000000002",
        prodIdentity: "20000000-0000-4000-8000-000000000003",
        betaSource: "30000000-0000-4000-8000-000000000001",
        prodSource: "30000000-0000-4000-8000-000000000003",
        media: "40000000-0000-4000-8000-000000000001",
        betaFight: "50000000-0000-4000-8000-000000000001",
        prodFight: "50000000-0000-4000-8000-000000000003",
        post: "60000000-0000-4000-8000-000000000001",
    };
    const betaRows: Record<string, TransferRow[]> = Object.fromEntries(
        transferTableValues.map((table) => [table, []]),
    );
    const prodRows: Record<string, TransferRow[]> = Object.fromEntries(
        transferTableValues.map((table) => [table, []]),
    );
    betaRows["auth.users"] = [
        { id: ids.beta, email: "shared@example.invalid", deleted_at: null },
        { id: ids.added, email: "new@example.invalid", deleted_at: null },
    ];
    prodRows["auth.users"] = [
        { id: ids.prod, email: "shared@example.invalid", deleted_at: null },
    ];
    betaRows["auth.identities"] = [
        {
            id: ids.betaIdentity,
            user_id: ids.beta,
            provider: "apple",
            provider_id: "apple-shared",
        },
        {
            id: ids.addedIdentity,
            user_id: ids.added,
            provider: "apple",
            provider_id: "apple-new",
        },
    ];
    prodRows["auth.identities"] = [
        {
            id: ids.prodIdentity,
            user_id: ids.prod,
            provider: "apple",
            provider_id: "apple-shared",
        },
    ];
    betaRows["public.profiles"] = [
        {
            user_id: ids.beta,
            handle: "beta-shared",
            display_name: "Beta name",
            referral_code: "BETA1",
            deleted_at: null,
            avatar_media_id: ids.media,
        },
        {
            user_id: ids.added,
            handle: "beta-new",
            display_name: "New person",
            referral_code: "BETA2",
            deleted_at: null,
            avatar_media_id: null,
        },
    ];
    prodRows["public.profiles"] = [
        {
            user_id: ids.prod,
            handle: "prod-shared",
            display_name: "Production name",
            referral_code: "PROD1",
            deleted_at: null,
            avatar_media_id: null,
        },
    ];
    betaRows["public.data_sources"] = [
        {
            id: ids.betaSource,
            user_id: ids.beta,
            provider: "healthkit",
            connection_route: "ios",
            last_success_at: "2026-09-15T12:00:00Z",
            revoked_at: null,
        },
    ];
    prodRows["public.data_sources"] = [
        {
            id: ids.prodSource,
            user_id: ids.prod,
            provider: "healthkit",
            connection_route: "ios",
            last_success_at: "2026-09-01T12:00:00Z",
            revoked_at: null,
        },
    ];
    betaRows["public.media_objects"] = [
        {
            id: ids.media,
            owner_id: ids.beta,
            status: "ready",
            bucket_id: "user-media",
            purpose: "profile",
            object_path: `${ids.beta}/profile/${ids.media}`,
            byte_size: 123,
            content_type: "image/jpeg",
            sha256: "a".repeat(64),
        },
    ];
    betaRows["public.fights"] = [
        {
            id: ids.betaFight,
            owner_id: ids.beta,
            name: "Beta fight",
            state: "final",
        },
    ];
    prodRows["public.fights"] = [
        {
            id: ids.prodFight,
            owner_id: ids.prod,
            name: "Production fight",
            state: "final",
        },
    ];
    betaRows["public.fight_members"] = [
        {
            fight_id: ids.betaFight,
            user_id: ids.beta,
            selected_source_id: ids.betaSource,
            current_value: 1234,
            final_value: 1234,
        },
    ];
    betaRows["public.fight_posts"] = [
        {
            id: ids.post,
            author_id: ids.beta,
            fight_id: ids.betaFight,
            body: `Literal text ${ids.beta}`,
        },
    ];

    const primaryKeys: Record<string, string[]> = {
        "public.profiles": ["user_id"],
        "public.fight_members": ["fight_id", "user_id"],
    };
    const userColumns: Record<string, string[]> = {
        "auth.identities": ["user_id"],
        "public.profiles": ["user_id"],
        "public.data_sources": ["user_id"],
        "public.media_objects": ["owner_id"],
        "public.fights": ["owner_id"],
        "public.fight_members": ["user_id"],
        "public.fight_posts": ["author_id"],
    };
    const definitions = Object.fromEntries(
        transferTableValues.map((table) => [
            table,
            {
                columns: Object.keys(
                    betaRows[table][0] ?? prodRows[table][0] ?? { id: "" },
                ).sort(),
                primary_key: primaryKeys[table] ?? ["id"],
                user_columns: userColumns[table] ?? [],
                source_columns:
                    table === "public.fight_members"
                        ? ["selected_source_id"]
                        : [],
            },
        ]),
    );
    const source = transferSnapshotSchema.parse({
        captured_at: "2026-09-15T12:00:00Z",
        project_ref: "zstzbfocunthczzubggz",
        definitions,
        rows: betaRows,
        pending_media: 2,
    });
    const target = transferSnapshotSchema.parse({
        captured_at: "2026-09-15T12:00:00Z",
        project_ref: "qkkhkfepjhdgowmhhpyf",
        definitions,
        rows: prodRows,
        pending_media: 0,
    });
    return { ids, source, target };
}

test("a shared Apple account keeps production identity, referrals, and history while importing beta references", () => {
    const { ids, source, target } = transferFixtures();
    assert.deepEqual(transferRequestSchema.parse({ action: "prepare" }), {
        action: "prepare",
        profile_policy: "beta",
    });
    assert.equal(
        transferRequestSchema.safeParse({
            action: "prepare",
            profile_policy: "production",
        }).success,
        false,
    );
    const before = structuredClone(target);
    const plan = planDataTransfer(source, target, null);
    assert.deepEqual(plan.conflicts, []);
    assert.equal(plan.total_accounts, 2);
    assert.equal(plan.shared_accounts, 1);
    assert.equal(plan.user_ids[ids.beta], ids.prod);
    assert.equal(plan.source_ids[ids.betaSource], ids.prodSource);
    assert.deepEqual(
        plan.after["auth.users"].find((row) => row.id === ids.prod),
        target.rows["auth.users"][0],
    );
    assert.equal(
        plan.after["auth.identities"].find(
            (row) => row.provider_id === "apple-shared",
        )?.id,
        ids.prodIdentity,
    );
    const profile = plan.after["public.profiles"].find(
        (row) => row.user_id === ids.prod,
    );
    assert.equal(profile?.handle, "beta-shared");
    assert.equal(profile?.referral_code, "PROD1");
    assert.deepEqual(
        plan.after["public.fights"].find((row) => row.id === ids.prodFight),
        target.rows["public.fights"][0],
    );
    assert.equal(
        plan.after["public.media_objects"][0].object_path,
        `${ids.prod}/profile/${ids.media}`,
    );
    assert.equal(
        plan.after["public.fight_members"][0].selected_source_id,
        ids.prodSource,
    );
    assert.equal(plan.after["public.fight_members"][0].final_value, 1234);
    assert.equal(
        plan.after["public.fight_posts"][0].body,
        `Literal text ${ids.beta}`,
    );
    assert.deepEqual(target, before);
});

test("beta profile details win on catch-up even when production also changed them", () => {
    for (const betaChanged of [false, true]) {
        const { ids, source, target } = transferFixtures();
        const first = planDataTransfer(source, target, null);
        const live = structuredClone({ ...target, rows: first.after });
        const shared = live.rows["public.profiles"].find(
            (row) => row.user_id === ids.prod,
        );
        assert.ok(shared);
        shared.handle = "prod-changed";
        shared.display_name = "Changed in production";
        shared.avatar_media_id = null;
        if (betaChanged) {
            source.rows["public.profiles"][0].handle = "beta-latest";
            source.rows["public.profiles"][0].display_name = "Latest beta name";
        }
        source.rows["public.profiles"][1].display_name = "Updated new person";
        const next = planDataTransfer(source, live, first);
        assert.deepEqual(next.conflicts, []);
        assert.equal(next.writes["public.profiles"].length, 2);
        assert.deepEqual(
            next.after["public.profiles"].find(
                (row) => row.user_id === ids.prod,
            ),
            {
                ...source.rows["public.profiles"][0],
                user_id: ids.prod,
                referral_code: "PROD1",
            },
        );
        assert.equal(
            next.after["public.profiles"].find(
                (row) => row.user_id === ids.added,
            )?.display_name,
            "Updated new person",
        );
    }
});

test("a catch-up import updates its own untouched rows and preserves unrelated production records", () => {
    const { ids, source, target } = transferFixtures();
    const first = planDataTransfer(source, target, null);
    source.rows["public.fight_posts"][0].body = "Beta edited the post";
    const next = planDataTransfer(
        source,
        { ...target, rows: first.after },
        first,
    );
    assert.deepEqual(next.conflicts, []);
    assert.equal(next.writes["public.fight_posts"].length, 1);
    assert.equal(
        next.after["public.fight_posts"][0].body,
        "Beta edited the post",
    );
    assert.deepEqual(
        next.after["public.fights"].find((row) => row.id === ids.prodFight),
        target.rows["public.fights"][0],
    );
});

test("a production edit remains protected across repeated catch-up runs", () => {
    const { source, target } = transferFixtures();
    const first = planDataTransfer(source, target, null);
    const live = structuredClone({ ...target, rows: first.after });
    live.rows["public.fight_posts"][0].body = "Edited in production";
    const second = planDataTransfer(source, live, first);
    assert.deepEqual(second.conflicts, []);
    assert.equal(second.writes["public.fight_posts"].length, 0);
    const third = planDataTransfer(source, live, second);
    assert.equal(third.writes["public.fight_posts"].length, 0);
    source.rows["public.fight_posts"][0].body = "A different beta edit";
    const conflict = planDataTransfer(source, live, third);
    assert.deepEqual(conflict.conflicts, [
        {
            table: "public.fight_posts",
            reason: "different_existing_record",
            count: 1,
        },
    ]);
});

test("source deletions are reported instead of deleting imported history", () => {
    const { source, target } = transferFixtures();
    const first = planDataTransfer(source, target, null);
    source.rows["public.fight_posts"] = [];
    const next = planDataTransfer(
        source,
        { ...target, rows: first.after },
        first,
    );
    assert.deepEqual(next.conflicts, [
        {
            table: "public.fight_posts",
            reason: "beta_deleted_imported_record",
            count: 1,
        },
    ]);
    assert.equal(next.after["public.fight_posts"].length, 1);
});

test("an imported record deleted in production is never resurrected", () => {
    const { source, target } = transferFixtures();
    const first = planDataTransfer(source, target, null);
    const live = structuredClone({ ...target, rows: first.after });
    live.rows["public.fight_posts"] = [];
    const next = planDataTransfer(source, live, first);
    assert.deepEqual(next.conflicts, [
        {
            table: "public.fight_posts",
            reason: "production_deleted_imported_record",
            count: 1,
        },
    ]);
    assert.equal(next.writes["public.fight_posts"].length, 0);
});

test("an unrelated production record with the same primary key blocks the import", () => {
    const { source, target } = transferFixtures();
    target.rows["public.fight_posts"] = [
        {
            ...source.rows["public.fight_posts"][0],
            body: "Independent production content",
        },
    ];
    const plan = planDataTransfer(source, target, null);
    assert.deepEqual(plan.conflicts, [
        {
            table: "public.fight_posts",
            reason: "different_existing_record",
            count: 1,
        },
    ]);
});

test("identity, email, and username collisions fail before preparing writes", () => {
    for (const collision of ["identity", "email", "username"]) {
        const { source, target } = transferFixtures();
        if (collision === "identity") source.rows["auth.identities"] = [];
        if (collision === "email")
            source.rows["auth.users"][1].email = "shared@example.invalid";
        if (collision === "username")
            source.rows["public.profiles"][1].handle = "prod-shared";
        assert.throws(() => planDataTransfer(source, target, null));
    }
});

test("schema drift and unexpected media ownership fail before preparing writes", () => {
    const { source, target } = transferFixtures();
    source.definitions["public.profiles"].columns.push("unexpected_column");
    assert.throws(
        () => planDataTransfer(source, target, null),
        /Schema differs/,
    );
    const fresh = transferFixtures();
    fresh.source.rows["public.media_objects"][0].object_path =
        "another-person/profile/image";
    assert.throws(
        () => planDataTransfer(fresh.source, fresh.target, null),
        /Unexpected media path/,
    );
});

test("digests ignore object key order but preserve ordered historical arrays", () => {
    assert.equal(
        transferDigest({ a: 1, b: { c: 2, d: 3 } }),
        transferDigest({ b: { d: 3, c: 2 }, a: 1 }),
    );
    assert.notEqual(
        transferDigest({ checkpoints: [1, 2] }),
        transferDigest({ checkpoints: [2, 1] }),
    );
});
