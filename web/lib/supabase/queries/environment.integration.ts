import assert from "node:assert/strict";
import { after, test } from "node:test";
import postgres from "postgres";
import { GET } from "@/app/api/v1/environment/route";
import { ApiError } from "@/lib/http";
import { closeDatabaseClientForTests } from "@/lib/supabase/postgres";
import { environmentResponseSchema } from "@/lib/types/environment/environment";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { readEnvironment } from "./environment-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 2 });
after(async () => {
    await closeDatabaseClientForTests();
    await database.end();
});

test("develop answers beta and main answers production from the environment table", async () => {
    assert.equal(
        await readEnvironment("zstzbfocunthczzubggz", database),
        "beta",
    );
    assert.equal(
        await readEnvironment("pvqntpteehdvhqyctwum", database),
        "production",
    );
    await assert.rejects(
        readEnvironment("qkkhkfepjhdgowmhhpyf", database),
        (error: unknown) => error instanceof ApiError && error.status === 503,
    );

    for (const [project, environment] of [
        ["https://zstzbfocunthczzubggz.supabase.co", "beta"],
        ["https://pvqntpteehdvhqyctwum.supabase.co/", "production"],
    ]) {
        process.env.NEXT_PUBLIC_SUPABASE_URL = project;
        const response = await GET(
            new Request("https://staging.fitfight.app/api/v1/environment"),
            { params: Promise.resolve({}) },
        );
        assert.equal(response.status, 200, "no sign-in is needed");
        assert.equal(response.headers.get("cache-control"), "no-store");
        assert.deepEqual(
            environmentResponseSchema.parse(await response.json()),
            { environment },
        );
    }
    process.env.NEXT_PUBLIC_SUPABASE_URL = "http://127.0.0.1:54321";
    const unknown = await GET(
        new Request("http://127.0.0.1:3000/api/v1/environment"),
        { params: Promise.resolve({}) },
    );
    assert.equal(unknown.status, 503);

    await assert.rejects(
        database`update private.environments set name = 'staging' where project_ref = 'zstzbfocunthczzubggz'`,
        /check constraint/,
    );
    for (const role of ["anon", "authenticated", "fitfight_backend_reader"]) {
        await assert.rejects(
            database.begin(async (transaction) => {
                await transaction`set local role ${database(role)}`;
                await transaction`select * from private.environments`;
            }),
            /permission denied/,
        );
    }
});
