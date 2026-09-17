import type { TransactionSql } from "postgres";

/** Series operations lock series before rounds, then members, including roster rollover. */
export async function lockFightSeries(sql: TransactionSql, fightId: string) {
    await sql`select id from public.fight_series where id = (
        select series_id from public.fights where id = ${fightId}
    ) for update`;
}
