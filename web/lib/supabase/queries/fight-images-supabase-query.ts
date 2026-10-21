import type { Fragment, JSONValue, Sql } from "postgres";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    fightImageCastRowSchema,
    fightImageConfiguration,
    fightImageJobRowSchema,
    fightImageWebpSourceRowSchema,
    type FightImageCastRow,
    type FightImageJobRow,
    type FightImageWebpSourceRow,
} from "@/lib/types/fight-images/fight-image";

const BUCKET = "fight-group-references";
const WEBP_BUCKET = "fight-group-images";
const SIGNED_SECONDS = 7 * 24 * 60 * 60;
const activeFightStates = ["scheduled", "live"];

/** md5 of a fight's accepted runners and their companions; it changes when anyone joins, leaves or switches. */
function castKey(sql: Sql, fightId: Fragment | string) {
    return sql`(
        select md5(string_agg(
            member.user_id::text || ':' || coalesce(profile.companion_id, '') || ':' || coalesce(profile.companion_image_url, ''),
            ',' order by member.user_id
        ))
        from public.fight_members as member
        join public.profiles as profile on profile.id = member.user_id and profile.deleted_at is null
        where member.fight_id = ${fightId} and member.state = 'accepted'
    )`;
}

/**
 * Opens a waiting image, due in an hour, for every running or upcoming fight with at least two runners whose
 * runners or companions differ from its last finished image. A fight already waiting or running is left alone,
 * so changes inside the hour fold into the one image. A new round of a repeating fight first reuses, at once,
 * the series' last ready image when its runners and companions are the same.
 */
export async function enqueueChangedFightImages(database: Sql = createDatabaseClient()) {
    await database`
        insert into private.fight_group_images (fight_id, status, due_at, finished_at, cast_key, layout, runners, image_url, webp_url, attempt_log)
        select fight.id, 'ready', now(), now(), previous.cast_key, previous.layout, previous.runners, previous.image_url,
            previous.webp_url, jsonb_build_array(jsonb_build_object('reused_from', previous.id))
        from public.fights as fight
        join lateral (
            select image.id, image.cast_key, image.layout, image.runners, image.image_url, image.webp_url
            from private.fight_group_images as image
            join public.fights as round on round.id = image.fight_id
            where round.series_id = fight.series_id and round.id <> fight.id and image.status = 'ready'
            order by image.finished_at desc, image.id desc
            limit 1
        ) as previous on true
        where fight.series_id is not null and fight.state::text = any(${activeFightStates}) and fight.ends_at > now()
            and not exists (select 1 from private.fight_group_images as own where own.fight_id = fight.id)
            and ${castKey(database, database`fight.id`)} = previous.cast_key
    `;
    const rows = await database`
        insert into private.fight_group_images (fight_id, due_at)
        select fight.id, now() + ${fightImageConfiguration.waitMinutes} * interval '1 minute'
        from public.fights as fight
        where fight.state::text = any(${activeFightStates}) and fight.ends_at > now()
            and (
                select count(*) from public.fight_members as member
                join public.profiles as profile on profile.id = member.user_id and profile.deleted_at is null
                where member.fight_id = fight.id and member.state = 'accepted'
            ) >= 2
            and not exists (
                select 1 from private.fight_group_images as open
                where open.fight_id = fight.id and open.status in ('waiting', 'running')
            )
            and ${castKey(database, database`fight.id`)} is distinct from (
                select last.cast_key from private.fight_group_images as last
                where last.fight_id = fight.id and last.status in ('ready', 'failed')
                order by last.created_at desc, last.id desc
                limit 1
            )
        on conflict (fight_id) where status in ('waiting', 'running') do nothing
        returning id
    `;
    return rows.length;
}

/**
 * Claims the next due image and marks it running with its first attempt. Holds it back when the app-wide
 * ceilings are reached, pushes it to when the fight's daily allowance frees, and cancels it when the fight
 * ended or has fewer than two runners. Returns null when nothing can start now.
 */
export async function claimNextFightImage(
    database: Sql = createDatabaseClient(),
): Promise<{ job: FightImageJobRow; cast: FightImageCastRow[] } | null> {
    return database.begin(async (sql) => {
        const [limits] = await sql`
            select count(*) filter (where status = 'running')::int as running,
                count(*) filter (where started_at > now() - interval '7 days')::int as started
            from private.fight_group_images
            where status = 'running' or started_at > now() - interval '7 days'
        `;
        if (
            limits.running >= fightImageConfiguration.maxRunning ||
            limits.started >= fightImageConfiguration.globalPerWeek
        )
            return null;
        for (;;) {
            const [due] = await sql`
                select image.id, image.fight_id, fight.state::text as fight_state, fight.ends_at > now() as open
                from private.fight_group_images as image
                join public.fights as fight on fight.id = image.fight_id
                where image.status = 'waiting' and image.due_at <= now()
                order by image.due_at, image.id
                limit 1
                for update of image skip locked
            `;
            if (!due) return null;
            const [allowance] = await sql`
                select count(*)::int as used, min(started_at) + interval '24 hours' as frees_at
                from (
                    select started_at from private.fight_group_images
                    where fight_id = ${due.fight_id} and started_at > now() - interval '24 hours'
                    order by started_at desc
                    limit ${fightImageConfiguration.perFightPerDay}
                ) as recent
            `;
            if (allowance.used >= fightImageConfiguration.perFightPerDay) {
                await sql`update private.fight_group_images set due_at = ${allowance.frees_at} where id = ${due.id}`;
                continue;
            }
            const cast = (
                await sql`
                    select member.user_id, member.user_id = fight.owner_id as is_owner, member.accepted_at,
                        profile.companion_id, profile.companion_prompt,
                        -- NOTE: the app equips the Resting level (in an armchair, under a blanket), so the image
                        -- model invented a different running outfit every time. The Pushing level of the same
                        -- character is already standing in its sports kit.
                        coalesce((
                            select running.image_url
                            from private.ai_library_images as equipped
                            join private.ai_library_images as running on running.request_id = equipped.request_id and running.stage = 'fit'
                            where equipped.user_id = member.user_id and equipped.image_url = profile.companion_image_url
                            limit 1
                        ), profile.companion_image_url) as companion_image_url
                    from public.fight_members as member
                    join public.fights as fight on fight.id = member.fight_id
                    join public.profiles as profile on profile.id = member.user_id and profile.deleted_at is null
                    where member.fight_id = ${due.fight_id} and member.state = 'accepted'
                    order by member.accepted_at nulls last, member.user_id
                `
            ).map((row) => fightImageCastRowSchema.parse(row));
            if (!activeFightStates.includes(due.fight_state) || !due.open || cast.length < 2) {
                await sql`
                    update private.fight_group_images
                    set status = 'cancelled', finished_at = now(), error = 'fight ended or has fewer than two runners'
                    where id = ${due.id}
                `;
                continue;
            }
            const [job] = await sql`
                update private.fight_group_images
                set status = 'running', attempts = 1, started_at = now(), run_id = null,
                    cast_key = ${castKey(sql, due.fight_id)}
                where id = ${due.id}
                returning id, fight_id, status, attempts, layout, workflow_id, run_id, inputs, runners, updated_at
            `;
            return { job: fightImageJobRowSchema.parse(job), cast };
        }
    });
}

/** Records the reference sheets and inputs of an image and the Blend run of its current attempt. */
export async function saveFightImageRun(
    id: string,
    run: {
        layout: string;
        runners: JSONValue;
        workflowId: string;
        inputs: JSONValue;
        runId: string;
    },
    database: Sql = createDatabaseClient(),
) {
    await database`
        update private.fight_group_images
        set layout = ${run.layout}, runners = ${database.json(run.runners)},
            workflow_id = ${run.workflowId}, inputs = ${database.json(run.inputs)}, run_id = ${run.runId}
        where id = ${id}
    `;
}

/** Running images that have a Blend run to read, plus ones whose start never recorded a run. */
export async function readRunningFightImages(database: Sql = createDatabaseClient()): Promise<FightImageJobRow[]> {
    const rows = await database`
        select id, fight_id, status, attempts, layout, workflow_id, run_id, inputs, runners, updated_at
        from private.fight_group_images
        where status = 'running'
        order by updated_at, id
    `;
    return rows.map((row) => fightImageJobRowSchema.parse(row));
}

/**
 * Closes the attempt of run runId. A pass makes the image ready; otherwise another attempt continues with
 * nextRunId, or the image fails and the fight keeps its previous image. A failure that never reached a judged
 * run (requeue) forgets its runners so the next pass queues the fight again. Only the cron that still sees
 * runId as the current run wins, so overlapping crons cannot close one attempt twice.
 */
export async function finishFightImageAttempt(
    id: string,
    attempt: {
        runId: string | null;
        imageUrl: string | null;
        check: string | null;
        problems: string[];
        pass: boolean;
        nextRunId?: string | null;
        requeue?: boolean;
    },
    database: Sql = createDatabaseClient(),
) {
    const log = { run_id: attempt.runId, image_url: attempt.imageUrl, check: attempt.check, problems: attempt.problems };
    if (attempt.pass) {
        await database`
            update private.fight_group_images
            set status = 'ready', image_url = ${attempt.imageUrl}, finished_at = now(),
                attempt_log = attempt_log || ${database.json([log])}::jsonb
            where id = ${id} and status = 'running' and run_id is not distinct from ${attempt.runId}
        `;
    } else if (attempt.nextRunId) {
        await database`
            update private.fight_group_images
            set attempts = attempts + 1, run_id = ${attempt.nextRunId},
                attempt_log = attempt_log || ${database.json([log])}::jsonb
            where id = ${id} and status = 'running' and run_id is not distinct from ${attempt.runId}
        `;
    } else {
        await database`
            update private.fight_group_images
            set status = 'failed', finished_at = now(), error = ${attempt.problems.join("; ").slice(0, 2000)},
                cast_key = case when ${attempt.requeue === true} then null else cast_key end,
                attempt_log = attempt_log || ${database.json([log])}::jsonb
            where id = ${id} and status = 'running' and run_id is not distinct from ${attempt.runId}
        `;
    }
}

/** Stores one reference sheet privately and returns a week-long signed link Blend can read. */
export async function uploadFightReferenceSheet(imageId: string, index: number, png: Buffer) {
    const storage = createAdminClient().storage.from(BUCKET);
    const path = `${imageId}/sheet-${index + 1}.png`;
    const uploaded = await storage.upload(path, png, { contentType: "image/png", upsert: true });
    if (uploaded.error) throw uploaded.error;
    const signed = await storage.createSignedUrl(path, SIGNED_SECONDS);
    if (signed.error || !signed.data) throw signed.error ?? new Error("reference sheet was not signed");
    return signed.data.signedUrl;
}

/** Ready images still served as Blend's PNG, newest first so a fresh image converts before old ones. */
export async function readUnconvertedFightImages(database: Sql = createDatabaseClient()): Promise<FightImageWebpSourceRow[]> {
    const rows = await database`
        select id, image_url from private.fight_group_images
        where status = 'ready' and image_url is not null and webp_url is null
        order by finished_at desc, id
    `;
    return rows.map((row) => fightImageWebpSourceRowSchema.parse(row));
}

/** Stores an image's WebP copy publicly, cached for a year (its path never changes), and serves it from then on. */
export async function saveFightImageWebp(imageId: string, webp: Buffer, database: Sql = createDatabaseClient()) {
    const storage = createAdminClient().storage.from(WEBP_BUCKET);
    const path = `${imageId}.webp`;
    const uploaded = await storage.upload(path, webp, { contentType: "image/webp", cacheControl: "31536000", upsert: true });
    if (uploaded.error) throw uploaded.error;
    const url = storage.getPublicUrl(path).data.publicUrl;
    await database`update private.fight_group_images set webp_url = ${url} where id = ${imageId}`;
}
