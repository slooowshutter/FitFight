import type { Sql, TransactionSql } from "postgres";
import { transferDigest } from "@/lib/releases/data-transfer";
import {
    transferForeignKeySchema,
    transferMediaSchema,
    transferSnapshotSchema,
    transferTableDefinitionSchema,
    transferTableValues,
    transferUserColumnValues,
    type TransferArchive,
    type TransferApplicationResult,
    type TransferRow,
    type TransferMedia,
    type TransferSnapshot,
    type TransferTableDefinition,
} from "@/lib/types/releases/data-transfer";

export async function readTransferMedia(
    database: Sql,
    id: string,
): Promise<TransferMedia | null> {
    const [row] = await database<{ media: unknown }[]>`
        select to_jsonb(media) as media from public.media_objects media
        where id = ${id}::uuid and status = 'ready'
    `;
    return row ? transferMediaSchema.parse(row.media) : null;
}

/** Call inside a repeatable-read transaction. Credentials, sessions, devices, and work queues are excluded. */
export async function readTransferSnapshot(
    database: TransactionSql,
    projectRef: string,
): Promise<TransferSnapshot> {
    const definitions: Record<string, TransferTableDefinition> = {};
    const rows: Record<string, TransferRow[]> = {};
    for (const table of transferTableValues) {
        const [definition] = await database<{ definition: unknown }[]>`
            select jsonb_build_object(
                'columns', (select jsonb_agg(a.attname order by a.attnum)
                    from pg_attribute a where a.attrelid = ${table}::regclass
                        and a.attnum > 0 and not a.attisdropped and a.attgenerated = ''),
                'primary_key', (select jsonb_agg(a.attname order by key.ordinality)
                    from pg_constraint c cross join lateral unnest(c.conkey) with ordinality as key(attnum, ordinality)
                    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = key.attnum
                    where c.conrelid = ${table}::regclass and c.contype = 'p'),
                'user_columns', coalesce((select jsonb_agg(distinct a.attname order by a.attname)
                    from pg_constraint c cross join lateral unnest(c.conkey) as key(attnum)
                    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = key.attnum
                    where c.conrelid = ${table}::regclass and c.contype = 'f'
                        and c.confrelid in ('auth.users'::regclass, 'public.profiles'::regclass)), '[]'::jsonb),
                'source_columns', coalesce((select jsonb_agg(distinct a.attname order by a.attname)
                    from pg_constraint c cross join lateral unnest(c.conkey) as key(attnum)
                    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = key.attnum
                    where c.conrelid = ${table}::regclass and c.contype = 'f'
                        and c.confrelid = 'public.data_sources'::regclass), '[]'::jsonb)
            ) as definition
        `;
        const parsed = transferTableDefinitionSchema.parse(
            definition.definition,
        );
        if (table === "auth.users")
            parsed.columns = [...transferUserColumnValues];
        definitions[table] = parsed;
        const columns = parsed.columns
            .map((column) => `"${column.replaceAll('"', '""')}"`)
            .join(", ");
        const filter =
            table === "public.media_objects" ? "where status = 'ready'" : "";
        const result = await database.unsafe<{ row: TransferRow }[]>(
            `select to_jsonb(record) as row from (select ${columns} from ${table} ${filter}) record`,
        );
        const keyed = result.map(({ row }) => ({
            key: JSON.stringify(
                parsed.primary_key.map((column) => row[column]),
            ),
            row,
        }));
        keyed.sort((left, right) =>
            left.key < right.key ? -1 : left.key > right.key ? 1 : 0,
        );
        rows[table] = keyed.map(({ row }) => row);
    }
    const [pending] = await database<
        { count: number }[]
    >`select count(*)::integer as count from public.media_objects where status <> 'ready'`;
    return transferSnapshotSchema.parse({
        captured_at: new Date().toISOString(),
        project_ref: projectRef,
        definitions,
        rows,
        pending_media: pending.count,
    });
}

/** The target must still match its prepared snapshot. All row writes and verification commit together. */
export async function applyDataTransfer(
    database: Sql,
    archive: TransferArchive,
    commit = false,
): Promise<TransferApplicationResult> {
    if (archive.plan.conflicts.length > 0)
        throw new Error("Transfer has unresolved conflicts");
    const rehearsalComplete = new Error("Transfer rehearsal completed");
    try {
        return await database.begin(
            "isolation level serializable",
            async (transaction) => {
                await transaction`set local lock_timeout = '5s'`;
                await transaction`set local statement_timeout = '60s'`;
                await transaction.unsafe(
                    `lock table ${[...transferTableValues].sort().join(", ")} in share row exclusive mode`,
                );
                const current = await readTransferSnapshot(
                    transaction,
                    archive.target.project_ref,
                );
                const currentDigest = transferDigest(current.rows);
                if (currentDigest === archive.plan.after_digest) {
                    return {
                        already_applied: true,
                        committed: true,
                        verified_digest: currentDigest,
                    };
                }
                if (currentDigest !== archive.plan.before_digest)
                    throw new Error(
                        "Target changed after transfer preparation",
                    );

                // Restore historical rows without signup defaults, score recalculation, or outgoing broadcasts.
                // Foreign keys are checked explicitly below before this transaction can commit.
                await transaction`set local session_replication_role = replica`;
                for (const table of transferTableValues) {
                    const records = archive.plan.writes[table];
                    if (records.length === 0) continue;
                    const definition = archive.target.definitions[table];
                    const columns = definition.columns.map(
                        (column) => `"${column.replaceAll('"', '""')}"`,
                    );
                    // Auth requires the zero instance ID and string tokens despite nullable SQL defaults.
                    // New accounts receive empty values; existing credentials are never copied or updated.
                    const payload =
                        table === "auth.users"
                            ? records.map((row) => ({
                                  ...row,
                                  instance_id:
                                      "00000000-0000-0000-0000-000000000000",
                                  confirmation_token: "",
                                  recovery_token: "",
                                  email_change_token_new: "",
                                  email_change: "",
                              }))
                            : records;
                    if (table === "auth.users")
                        columns.push(
                            '"instance_id"',
                            '"confirmation_token"',
                            '"recovery_token"',
                            '"email_change_token_new"',
                            '"email_change"',
                        );
                    const keys = definition.primary_key.map(
                        (column) => `"${column.replaceAll('"', '""')}"`,
                    );
                    const updates = definition.columns
                        .filter(
                            (column) =>
                                !definition.primary_key.includes(column),
                        )
                        .map(
                            (column) =>
                                `"${column.replaceAll('"', '""')}" = excluded."${column.replaceAll('"', '""')}"`,
                        );
                    const conflict =
                        updates.length > 0
                            ? `do update set ${updates.join(", ")}`
                            : "do nothing";
                    // Bind encoded rows as text so postgres.js cannot JSON-encode the string again.
                    await transaction.unsafe(
                        `insert into ${table} (${columns.join(", ")})
                 select ${columns.join(", ")} from jsonb_populate_recordset(null::${table}, $1::text::jsonb)
                 on conflict (${keys.join(", ")}) ${conflict}`,
                        [JSON.stringify(payload)],
                    );
                }

                await transaction`set local session_replication_role = origin`;
                const foreignKeys = transferForeignKeySchema.array().parse(
                    await transaction`
            select quote_ident(child_namespace.nspname) || '.' || quote_ident(child.relname) as child,
                quote_ident(parent_namespace.nspname) || '.' || quote_ident(parent.relname) as parent,
                constraint_row.confmatchtype as match_kind,
                array(select attribute.attname from unnest(constraint_row.conkey) with ordinality key(attnum, position)
                    join pg_attribute attribute on attribute.attrelid = child.oid and attribute.attnum = key.attnum
                    order by key.position) as child_columns,
                array(select attribute.attname from unnest(constraint_row.confkey) with ordinality key(attnum, position)
                    join pg_attribute attribute on attribute.attrelid = parent.oid and attribute.attnum = key.attnum
                    order by key.position) as parent_columns
            from pg_constraint constraint_row
            join pg_class child on child.oid = constraint_row.conrelid
            join pg_namespace child_namespace on child_namespace.oid = child.relnamespace
            join pg_class parent on parent.oid = constraint_row.confrelid
            join pg_namespace parent_namespace on parent_namespace.oid = parent.relnamespace
            where constraint_row.contype = 'f'
                and child_namespace.nspname || '.' || child.relname in (
                    select jsonb_array_elements_text(${transaction.json([...transferTableValues])}::jsonb)
                )
        `,
                );
                for (const foreignKey of foreignKeys) {
                    const childColumns = foreignKey.child_columns.map(
                        (column) => `"${column.replaceAll('"', '""')}"`,
                    );
                    const parentColumns = foreignKey.parent_columns.map(
                        (column) => `"${column.replaceAll('"', '""')}"`,
                    );
                    const present = childColumns
                        .map((column) => `child.${column} is not null`)
                        .join(" and ");
                    const matches = childColumns
                        .map(
                            (column, index) =>
                                `parent.${parentColumns[index]} = child.${column}`,
                        )
                        .join(" and ");
                    const [violations] = await transaction.unsafe<
                        { count: number }[]
                    >(
                        `select count(*)::integer as count from ${foreignKey.child} child where ${present}
                 and not exists (select 1 from ${foreignKey.parent} parent where ${matches})`,
                    );
                    if (violations.count !== 0)
                        throw new Error(
                            "Imported reference is missing its parent",
                        );
                }
                const verified = await readTransferSnapshot(
                    transaction,
                    archive.target.project_ref,
                );
                const digest = transferDigest(verified.rows);
                if (digest !== archive.plan.after_digest)
                    throw new Error(
                        "Imported rows differ from the prepared result",
                    );
                if (!commit) throw rehearsalComplete;
                return {
                    already_applied: false,
                    committed: true,
                    verified_digest: digest,
                };
            },
        );
    } catch (error) {
        if (error !== rehearsalComplete) throw error;
        return {
            already_applied: false,
            committed: false,
            verified_digest: archive.plan.after_digest,
        };
    }
}
