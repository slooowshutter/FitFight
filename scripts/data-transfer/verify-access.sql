-- Replays the released build 113 read columns for every account and an unrelated identity.
-- Expected visibility comes from the data, then both actual RLS roles must match it.
begin;
do $$
declare
    account_id uuid;
    account_ids uuid[];
    reader_role text;
    visible_fights uuid[];
    roster_fights uuid[];
    expected_counts bigint[];
    actual_counts bigint[];
    checked integer := 0;
begin
    select array_agg(id order by id) || gen_random_uuid() into account_ids from auth.users;
    foreach account_id in array account_ids loop
        select coalesce(array_agg(id), '{}') into visible_fights from public.fights f
        where f.owner_id = account_id or exists (
            select 1 from public.fight_members m where m.fight_id = f.id
                and m.user_id = account_id and m.state in ('invited', 'accepted', 'deferred')
        );
        select coalesce(array_agg(fight_id), '{}') into roster_fights from public.fight_members
        where user_id = account_id and state in ('accepted', 'deferred');
        select array[
            (select count(*) from public.profiles where deleted_at is null),
            (select count(*) from public.fights where id = any(visible_fights)),
            (select count(*) from public.fight_members where user_id = account_id or fight_id = any(roster_fights)),
            (select count(*) from public.step_days d where d.user_id = account_id or exists (
                select 1 from public.fight_members peer join public.fights f on f.id = peer.fight_id
                where peer.fight_id = any(roster_fights) and peer.user_id = d.user_id and peer.state = 'accepted'
                    and d.day >= (f.starts_at at time zone f.time_zone)::date
                    and d.day <= ((f.ends_at - interval '1 microsecond') at time zone f.time_zone)::date
            ))
        ] into expected_counts;
        perform set_config('request.jwt.claim.sub', account_id::text, true);
        foreach reader_role in array array['authenticated', 'fitfight_backend_reader'] loop
            execute format('set local role %I', reader_role);
            select array[
                (select count(*) from (select user_id,handle,display_name from public.profiles) p),
                (select count(*) from (select id,owner_id,name,state,starts_at,ends_at,action_text from public.fights) f),
                (select count(*) from (select fight_id,user_id,state,current_value,rank,final_value from public.fight_members) m),
                (select count(*) from (select user_id,day,steps from public.step_days) d)
            ] into actual_counts;
            reset role;
            if actual_counts <> expected_counts then
                raise exception 'Transferred data visibility differs for role %', reader_role;
            end if;
            checked := checked + 1;
        end loop;
    end loop;
    perform set_config('fitfight.transfer_access_checks', checked::text, true);
end $$;
select current_setting('fitfight.transfer_access_checks')::integer as account_role_checks,
    'passed' as transferred_data_access;
rollback;
