import assert from "node:assert/strict";
import { test } from "node:test";
import { GET } from "@/app/api/app-release/route";
import { ApiError } from "@/lib/http";
import { appReleasePolicy, requireLatestAppRelease } from "./app-release";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";

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

test("TestFlight users can continue when Apple has no update for their installed build", async (t) => {
    const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
    process.env.NEXT_PUBLIC_SUPABASE_URL =
        "https://zstzbfocunthczzubggz.supabase.co";
    t.after(() => {
        if (previousProject === undefined)
            delete process.env.NEXT_PUBLIC_SUPABASE_URL;
        else process.env.NEXT_PUBLIC_SUPABASE_URL = previousProject;
    });
    t.mock.method(globalThis, "fetch", async () =>
        Response.json({
            ...manifest,
            staging: {
                latest: {
                    version: "1.0.0",
                    build: 190,
                    update_url: "itms-beta://",
                },
                review: {
                    version: "1.1.0",
                    build: 200,
                    update_url: "itms-beta://",
                },
                internal: {
                    version: "1.1.0",
                    build: 200,
                    update_url: "itms-beta://",
                },
                enforced: true,
            },
        }),
    );
    for (const [version, build] of [
        ["1.0.0", "189"],
        ["1.0.0", "190"],
        ["1.1.0", "199"],
        ["1.1.0", "200"],
        ["1.1.1", "201"],
    ]) {
        await assert.doesNotReject(
            requireLatestAppRelease(
                new Request("https://staging.fitfight.app/api/v1/me", {
                    headers: {
                        "X-FitFight-Version": version,
                        "X-FitFight-Build": build,
                    },
                }),
            ),
        );
    }
    const response = await GET(
        new Request("https://staging.fitfight.app/api/app-release"),
        { params: Promise.resolve({}) },
    );
    assert.equal((await response.json()).enforced, false);
});

test("TestFlight version headers never prevent API access", async (t) => {
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
    for (const headers of [
        undefined,
        { "X-FitFight-Version": "1.0.0", "X-FitFight-Build": "159" },
        { "X-FitFight-Version": "1.0.0", "X-FitFight-Build": "161" },
        { "X-FitFight-Version": "1.1.0", "X-FitFight-Build": "160" },
        { "X-FitFight-Version": "1.0.0", "X-FitFight-Build": "0160" },
    ]) {
        await assert.doesNotReject(
            requireLatestAppRelease(
                new Request("https://staging.fitfight.app/api/v1/fights", {
                    headers,
                }),
            ),
        );
    }
    await requireLatestAppRelease(
        new Request("https://staging.fitfight.app/api/v1/fights", {
            headers: {
                "X-FitFight-Version": "1.0.0",
                "X-FitFight-Build": "160",
            },
        }),
    );
    assert.equal(fetch.mock.calls[0].arguments[1]?.cache, "no-store");
});

test("production admits its live build and the selected Apple review candidate, never a staging build", async (t) => {
    const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
    process.env.NEXT_PUBLIC_SUPABASE_URL =
        "https://pvqntpteehdvhqyctwum.supabase.co";
    t.after(() => {
        if (previousProject === undefined)
            delete process.env.NEXT_PUBLIC_SUPABASE_URL;
        else process.env.NEXT_PUBLIC_SUPABASE_URL = previousProject;
    });
    t.mock.method(globalThis, "fetch", async () => Response.json(manifest));
    for (const [version, build] of [
        ["1.0.0", "150"],
        ["1.1.0", "165"],
    ]) {
        await requireLatestAppRelease(
            new Request("https://fitfight.app/api/v1/fights", {
                headers: {
                    "X-FitFight-Version": version,
                    "X-FitFight-Build": build,
                },
            }),
        );
    }
    await assert.rejects(
        requireLatestAppRelease(
            new Request("https://fitfight.app/api/v1/fights", {
                headers: {
                    "X-FitFight-Version": "1.0.0",
                    "X-FitFight-Build": "160",
                },
            }),
        ),
        (error: unknown) => error instanceof ApiError && error.status === 426,
    );
});

test("internal TestFlight latest is admitted without making the public build mandatory", async (t) => {
    const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
    process.env.NEXT_PUBLIC_SUPABASE_URL =
        "https://zstzbfocunthczzubggz.supabase.co";
    t.after(() => {
        if (previousProject === undefined)
            delete process.env.NEXT_PUBLIC_SUPABASE_URL;
        else process.env.NEXT_PUBLIC_SUPABASE_URL = previousProject;
    });
    t.mock.method(globalThis, "fetch", async () =>
        Response.json({
            ...manifest,
            staging: {
                latest: {
                    version: "1.0.0",
                    build: 184,
                    update_url: "itms-beta://",
                },
                review: {
                    version: "1.0.0",
                    build: 187,
                    update_url: "itms-beta://",
                },
                internal: {
                    version: "1.0.0",
                    build: 187,
                    update_url: "itms-beta://",
                },
                enforced: true,
            },
        }),
    );
    for (const build of ["184", "187"]) {
        await requireLatestAppRelease(
            new Request("https://staging.fitfight.app/api/v1/fights", {
                headers: {
                    "X-FitFight-Version": "1.0.0",
                    "X-FitFight-Build": build,
                },
            }),
        );
    }
    for (const build of ["183", "185", "186"]) {
        await assert.doesNotReject(
            requireLatestAppRelease(
                new Request("https://staging.fitfight.app/api/v1/fights", {
                    headers: {
                        "X-FitFight-Version": "1.0.0",
                        "X-FitFight-Build": build,
                    },
                }),
            ),
        );
    }
});

test("a registered TestFlight review build can run before public availability", async (t) => {
    const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
    process.env.NEXT_PUBLIC_SUPABASE_URL =
        "https://zstzbfocunthczzubggz.supabase.co";
    t.after(() => {
        if (previousProject === undefined)
            delete process.env.NEXT_PUBLIC_SUPABASE_URL;
        else process.env.NEXT_PUBLIC_SUPABASE_URL = previousProject;
    });
    t.mock.method(globalThis, "fetch", async () =>
        Response.json({
            ...manifest,
            staging: {
                ...manifest.staging,
                review: {
                    version: "1.0.0",
                    build: 170,
                    update_url: "itms-beta://",
                },
            },
        }),
    );
    for (const build of ["160", "170"]) {
        await requireLatestAppRelease(
            new Request("https://staging.fitfight.app/api/v1/fights", {
                headers: {
                    "X-FitFight-Version": "1.0.0",
                    "X-FitFight-Build": build,
                },
            }),
        );
    }
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
    assert.deepEqual(await response.json(), manifest.prod);
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
    await requireLatestAppRelease(
        new Request("https://staging.fitfight.app/api/v1/fights", {
            headers: {
                "X-FitFight-Version": "1.0.0",
                "X-FitFight-Build": "190",
            },
        }),
    );
    await requireLatestAppRelease(
        new Request("https://staging.fitfight.app/api/v1/fights", {
            headers: {
                "X-FitFight-Version": "1.0.0",
                "X-FitFight-Build": "198",
            },
        }),
    );
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

test("authenticated commands stay usable when the release manifest cannot be read", async (t) => {
    const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
    process.env.NEXT_PUBLIC_SUPABASE_URL =
        "https://zstzbfocunthczzubggz.supabase.co";
    t.after(() => {
        if (previousProject === undefined)
            delete process.env.NEXT_PUBLIC_SUPABASE_URL;
        else process.env.NEXT_PUBLIC_SUPABASE_URL = previousProject;
    });
    t.mock.method(
        globalThis,
        "fetch",
        async () => new Response("Unavailable", { status: 503 }),
    );
    await requireLatestAppRelease(
        new Request("https://staging.fitfight.app/api/v1/fights", {
            headers: {
                "X-FitFight-Version": "1.0.0",
                "X-FitFight-Build": "190",
            },
        }),
    );
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

test("old production binaries are rejected before database or auth-provider calls", async (t) => {
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
    await assert.rejects(
        verifyUser(
            new Request("https://fitfight.app/api/v1/fights", {
                headers: { Authorization: "Bearer old-app-token" },
            }),
        ),
        (error: unknown) => error instanceof ApiError && error.status === 426,
    );
    assert.equal(fetch.mock.callCount(), 1);
});

test("the first deployment preserves old clients until a build containing the gate is installable", async (t) => {
    const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
    process.env.NEXT_PUBLIC_SUPABASE_URL =
        "https://zstzbfocunthczzubggz.supabase.co";
    t.after(() => {
        if (previousProject === undefined)
            delete process.env.NEXT_PUBLIC_SUPABASE_URL;
        else process.env.NEXT_PUBLIC_SUPABASE_URL = previousProject;
    });
    t.mock.method(globalThis, "fetch", async () =>
        Response.json({
            ...manifest,
            staging: { ...manifest.staging, enforced: false },
        }),
    );
    await requireLatestAppRelease(
        new Request("https://staging.fitfight.app/api/v1/fights"),
    );
});

test("continuing on an older TestFlight build still requires authentication and an active account", async (t) => {
    const previousProject = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const previousKey = process.env.SUPABASE_SECRET_KEY;
    process.env.NEXT_PUBLIC_SUPABASE_URL =
        "https://zstzbfocunthczzubggz.supabase.co";
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
    t.mock.method(
        globalThis,
        "fetch",
        async (input: RequestInfo | URL, init?: RequestInit) => {
            const url = new URL(new Request(input, init).url);
            if (url.hostname === "raw.githubusercontent.com")
                return Response.json(manifest);
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
            assert.equal(url.searchParams.get("user_id"), `eq.${userId}`);
            assert.equal(url.searchParams.get("deleted_at"), "is.null");
            return Response.json(deleted ? [] : [{ user_id: userId }]);
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
    const request = new Request("https://staging.fitfight.app/api/v1/me", {
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
        (error: unknown) => error instanceof ApiError && error.status === 401,
    );
    signedIn = false;
    await assert.rejects(
        verifyUser(request),
        (error: unknown) => error instanceof ApiError && error.status === 401,
    );
});
