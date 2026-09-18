import type { Sql } from "postgres";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import type { AiHttpLog } from "@/lib/types/ai/observation";

/** Seven days and at most 100,000 safe HTTP summaries per environment. Empty batches run scheduled retention. */
export async function insertAiHttpLogs(
    rows: AiHttpLog[],
    database: Sql = createDatabaseClient(),
) {
    await database.begin(async (sql) => {
        await sql`select pg_advisory_xact_lock(hashtext('fitfight:ai:logs'))`;
        // The account can disappear while an upstream call is in flight.
        if (rows.length > 0)
            await sql`
            insert into private.ai_http_logs
            select l.id, l.observed_at, l.trace_id, p.user_id, l.request_id, l.leg, l.operation,
                l.workflow_id, l.version_id, l.run_id, l.status, l.elapsed_ms, l.disposition, l.outcome, l.code, l.upstream_code
            from jsonb_to_recordset(${sql.json(rows)}) as l(
                id uuid, observed_at timestamptz, trace_id uuid, user_id uuid, request_id uuid, leg text,
                operation text, workflow_id text, version_id text, run_id text, status integer,
                elapsed_ms integer, disposition text, outcome text, code text, upstream_code text
            ) left join public.profiles p on p.user_id = l.user_id
            where l.user_id is null or p.user_id is not null
        `;
        await sql`delete from private.ai_http_logs where observed_at < clock_timestamp() - interval '7 days'`;
        await sql`delete from private.ai_http_logs where id in (
            select id from private.ai_http_logs order by observed_at desc, id desc offset 100000
        )`;
    });
}
