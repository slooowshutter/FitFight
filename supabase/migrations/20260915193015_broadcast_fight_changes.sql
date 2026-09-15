-- Only invalidations cross Realtime. The authenticated API owns snapshot access.
create policy "Receive own fight invalidations"
on realtime.messages for select to authenticated
using (
    extension = 'broadcast'
    and realtime.topic() = 'fitfight:fights:' || (select auth.uid())::text
);

create function private.broadcast_fight_changes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    changed_fights uuid[];
    changed_users uuid[] := '{}';
    recipient uuid;
begin
    if tg_table_name = 'fights' then
        select array_agg(n.id) into changed_fights
        from new_rows n join old_rows o using (id)
        where (to_jsonb(n) - 'updated_at') is distinct from (to_jsonb(o) - 'updated_at');
    elsif tg_op = 'INSERT' then
        select array_agg(fight_id), array_agg(user_id) into changed_fights, changed_users from new_rows;
    elsif tg_op = 'DELETE' then
        select array_agg(fight_id), array_agg(user_id) into changed_fights, changed_users from old_rows;
    else
        select array_agg(n.fight_id), array_agg(n.user_id) into changed_fights, changed_users
        from new_rows n join old_rows o using (fight_id, user_id)
        where to_jsonb(n) is distinct from to_jsonb(o);
    end if;

    -- Statement triggers deduplicate participants when a sync reranks several rows.
    for recipient in
        select m.user_id from public.fight_members m
        where m.fight_id = any(changed_fights) and m.state in ('accepted', 'invited', 'deferred')
        union
        select f.owner_id from public.fights f where f.id = any(changed_fights)
        union
        select unnest(changed_users)
    loop
        perform realtime.send('{}'::jsonb, 'fights_changed', 'fitfight:fights:' || recipient::text, true);
    end loop;
    return null;
end;
$$;

revoke all on function private.broadcast_fight_changes() from public, anon, authenticated;

create trigger fight_members_broadcast_insert
after insert on public.fight_members
referencing new table as new_rows
for each statement execute function private.broadcast_fight_changes();

create trigger fight_members_broadcast_update
after update on public.fight_members
referencing old table as old_rows new table as new_rows
for each statement execute function private.broadcast_fight_changes();

create trigger fight_members_broadcast_delete
after delete on public.fight_members
referencing old table as old_rows
for each statement execute function private.broadcast_fight_changes();

create trigger fights_broadcast_update
after update on public.fights
referencing old table as old_rows new table as new_rows
for each statement execute function private.broadcast_fight_changes();
