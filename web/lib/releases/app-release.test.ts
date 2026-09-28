import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";
import { GET } from "@/app/api/app-release/route";
import { ApiError } from "@/lib/http";
import {
    appReleasePolicy,
    resetAppReleasePolicyCacheForTests,
} from "./app-release";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";

beforeEach(() => resetAppReleasePolicyCacheForTests());

const manifest = {
    staging: {
        latest: { version: "1.0.0", build: 160, update_url: "itms-beta://" },
        review: null,
        enforced: true,
    },
    prod: {
        latest: {
            version: "1.0.0",
            build: 150,
            update_url: "https://apps.apple.com/app/id1234",
        },
        review: {
            version: "1.1.0",
            build: 165,
            update_url: "https://apps.apple.com/app/id1234",
        },
        enforced: true,
    },
};

test("the release manifest is always fetched fresh", async (t) => {
    const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
    process.env.NEXT_PUBLIC_SUPABASE_URL =
        "https://zstzbfocunthczzubggz.supabase.co";
    t.after(() => {
        if (previousProject === undefined)
            delete process.env.NEXT_PUBLIC_SUPABASE_URL;
        else process.env.NEXT_PUBLIC_SUPABASE_URL = previousProject;
    });
    const fetch = t.mock.method(globalThis, "fetch", async () =>
        Response.json(manifest),
    );
    await appReleasePolicy();
    assert.equal(fetch.mock.calls[0].arguments[1]?.cache, "no-store");
});

test("the public version check is available without auth and never cached", async (t) => {
    const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
    process.env.NEXT_PUBLIC_SUPABASE_URL =
        "https://pvqntpteehdvhqyctwum.supabase.co/";
    t.after(() => {
        if (previousProject === undefined)
            delete process.env.NEXT_PUBLIC_SUPABASE_URL;
        else process.env.NEXT_PUBLIC_SUPABASE_URL = previousProject;
    });
    t.mock.method(globalThis, "fetch", async () => Response.json(manifest));
    const response = await GET(
        new Request("https://fitfight.app/api/app-release"),
        { params: Promise.resolve({}) },
    );
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("cache-control"), "no-store");
    assert.deepEqual(await response.json(), {
        ...manifest.prod,
        enforced: false,
    });
});

test("the public version check returns the internal TestFlight latest when present", async (t) => {
    const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
    process.env.NEXT_PUBLIC_SUPABASE_URL =
        "https://zstzbfocunthczzubggz.supabase.co";
    t.after(() => {
        if (previousProject === undefined)
            delete process.env.NEXT_PUBLIC_SUPABASE_URL;
        else process.env.NEXT_PUBLIC_SUPABASE_URL = previousProject;
    });
    const staging = {
        latest: { version: "1.0.0", build: 184, update_url: "itms-beta://" },
        review: { version: "1.0.0", build: 187, update_url: "itms-beta://" },
        internal: { version: "1.0.0", build: 187, update_url: "itms-beta://" },
        enforced: true,
    };
    t.mock.method(globalThis, "fetch", async () =>
        Response.json({ ...manifest, staging }),
    );
    const response = await GET(
        new Request("https://staging.fitfight.app/api/app-release"),
        { params: Promise.resolve({}) },
    );
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ...staging, enforced: false });
});

test("a two-part App Store version does not block the staging TestFlight policy", async (t) => {
    const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
    process.env.NEXT_PUBLIC_SUPABASE_URL =
        "https://zstzbfocunthczzubggz.supabase.co";
    t.after(() => {
        if (previousProject === undefined)
            delete process.env.NEXT_PUBLIC_SUPABASE_URL;
        else process.env.NEXT_PUBLIC_SUPABASE_URL = previousProject;
    });
    const live = {
        staging: {
            latest: {
                version: "1.0.0",
                build: 190,
                update_url: "itms-beta://",
            },
            review: {
                version: "1.0.0",
                build: 198,
                update_url: "itms-beta://",
            },
            internal: {
                version: "1.0.0",
                build: 198,
                update_url: "itms-beta://",
            },
            enforced: true,
        },
        prod: {
            latest: {
                version: "1.0",
                build: 113,
                update_url: "https://apps.apple.com/app/id6804230516",
            },
            review: null,
            internal: null,
            enforced: false,
        },
    };
    t.mock.method(globalThis, "fetch", async () => Response.json(live));
    const response = await GET(
        new Request("https://staging.fitfight.app/api/app-release"),
        { params: Promise.resolve({}) },
    );
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
        ...live.staging,
        enforced: false,
    });
});

test("a broken production channel still serves a valid staging policy", async (t) => {
    const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
    process.env.NEXT_PUBLIC_SUPABASE_URL =
        "https://zstzbfocunthczzubggz.supabase.co";
    t.after(() => {
        if (previousProject === undefined)
            delete process.env.NEXT_PUBLIC_SUPABASE_URL;
        else process.env.NEXT_PUBLIC_SUPABASE_URL = previousProject;
    });
    const staging = {
        latest: { version: "1.0.0", build: 190, update_url: "itms-beta://" },
        review: { version: "1.0.0", build: 198, update_url: "itms-beta://" },
        internal: { version: "1.0.0", build: 198, update_url: "itms-beta://" },
        enforced: true,
    };
    t.mock.method(globalThis, "fetch", async () =>
        Response.json({
            staging,
            prod: {
                latest: {
                    version: "1.0.0",
                    build: 1,
                    update_url: "https://evil.example",
                },
                review: null,
                enforced: false,
            },
        }),
    );
    const response = await GET(
        new Request("https://staging.fitfight.app/api/app-release"),
        { params: Promise.resolve({}) },
    );
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ...staging, enforced: false });
});

test("unavailable or malformed release metadata never admits a client", async (t) => {
    const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
    process.env.NEXT_PUBLIC_SUPABASE_URL =
        "https://pvqntpteehdvhqyctwum.supabase.co";
    t.after(() => {
        if (previousProject === undefined)
            delete process.env.NEXT_PUBLIC_SUPABASE_URL;
        else process.env.NEXT_PUBLIC_SUPABASE_URL = previousProject;
    });
    for (const response of [
        new Response("Unavailable", { status: 503 }),
        new Response("invalid json"),
        Response.json({ prod: { latest: { version: "1.0.0", build: "150" } } }),
        Response.json({
            ...manifest,
            prod: {
                ...manifest.prod,
                latest: {
                    ...manifest.prod.latest,
                    update_url: "https://evil.example",
                },
            },
        }),
    ]) {
        const fetch = t.mock.method(globalThis, "fetch", async () => response);
        await assert.rejects(
            appReleasePolicy(),
            (error: unknown) =>
                error instanceof ApiError && error.status === 503,
        );
        fetch.mock.restore();
    }
    t.mock.method(globalThis, "fetch", async () => {
        throw new Error("offline");
    });
    await assert.rejects(
        appReleasePolicy(),
        (error: unknown) => error instanceof ApiError && error.status === 503,
    );
});

test("older builds on every channel skip the release check but still require an active account", async (t) => {
    const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const previousKey = process.env.SUPABASE_SECRET_KEY;
    process.env.SUPABASE_SECRET_KEY = "test-only-key";
    t.after(() => {
        if (previousProject === undefined)
            delete process.env.NEXT_PUBLIC_SUPABASE_URL;
        else process.env.NEXT_PUBLIC_SUPABASE_URL = previousProject;
        if (previousKey === undefined) delete process.env.SUPABASE_SECRET_KEY;
        else process.env.SUPABASE_SECRET_KEY = previousKey;
    });
    const userId = "11111111-1111-4111-8111-111111111111";
    let signedIn = true;
    let deleted = false;
    let manifestReads = 0;
    t.mock.method(
        globalThis,
        "fetch",
        async (input: RequestInfo | URL, init?: RequestInit) => {
            const url = new URL(new Request(input, init).url);
            if (url.hostname === "raw.githubusercontent.com") {
                manifestReads += 1;
                return Response.json(manifest);
            }
            if (url.pathname === "/auth/v1/user") {
                return signedIn
                    ? Response.json({
                          id: userId,
                          app_metadata: {},
                          user_metadata: {},
                          aud: "authenticated",
                          created_at: "2026-09-01T00:00:00Z",
                      })
                    : Response.json(
                          { message: "Invalid token" },
                          { status: 401 },
                      );
            }
            assert.equal(url.pathname, "/rest/v1/profiles");
            assert.equal(url.searchParams.get("id"), `eq.${userId}`);
            assert.equal(url.searchParams.get("deleted_at"), "is.null");
            return Response.json(deleted ? [] : [{ id: userId }]);
        },
    );
    const token =
        [
            { alg: "HS256", typ: "JWT" },
            { sub: userId, exp: 4102444800 },
        ]
            .map((part) =>
                Buffer.from(JSON.stringify(part)).toString("base64url"),
            )
            .join(".") + ".dGVzdA";
    for (const [project, origin] of [
        [
            "https://zstzbfocunthczzubggz.supabase.co",
            "https://staging.fitfight.app",
        ],
        ["https://pvqntpteehdvhqyctwum.supabase.co", "https://fitfight.app"],
    ]) {
        process.env.NEXT_PUBLIC_SUPABASE_URL = project;
        signedIn = true;
        deleted = false;
        const request = new Request(`${origin}/api/v1/me`, {
            headers: {
                Authorization: `Bearer ${token}`,
                "X-FitFight-Version": "1.0.0",
                "X-FitFight-Build": "159",
            },
        });
        assert.deepEqual(await verifyUser(request), { userId });
        deleted = true;
        await assert.rejects(
            verifyUser(request),
            (error: unknown) =>
                error instanceof ApiError && error.status === 401,
        );
        signedIn = false;
        await assert.rejects(
            verifyUser(request),
            (error: unknown) =>
                error instanceof ApiError && error.status === 401,
        );
    }
    assert.equal(manifestReads, 0);
});

test("a second policy read within a minute reuses the last manifest", async (t) => {
    const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
    process.env.NEXT_PUBLIC_SUPABASE_URL =
        "https://pvqntpteehdvhqyctwum.supabase.co";
    t.after(() => {
        if (previousProject === undefined)
            delete process.env.NEXT_PUBLIC_SUPABASE_URL;
        else process.env.NEXT_PUBLIC_SUPABASE_URL = previousProject;
    });
    const fetch = t.mock.method(globalThis, "fetch", async () =>
        Response.json(manifest),
    );
    await appReleasePolicy();
    assert.deepEqual(await appReleasePolicy(), {
        ...manifest.prod,
        enforced: false,
    });
    assert.equal(fetch.mock.callCount(), 1);
});
