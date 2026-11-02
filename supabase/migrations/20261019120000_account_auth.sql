begin;

-- The admin dashboard's Users table shows each account's email and sign-in providers. They live in
-- auth.users, which Supabase keeps from the production dashboard's read-only user
-- (docs/backend.md#admin-dashboard-prepared-29-sep-2026). The view reads them with its owner's
-- rights and copies nothing. No timestamp columns: it is not a table.
create view private.account_auth as
select users.id as user_id,
    users.email::text as email,
    array(select jsonb_path_query(users.raw_app_meta_data, '$.providers[*]') #>> '{}') as providers
from auth.users as users;

revoke all on private.account_auth from public, anon, authenticated, service_role;

do $$
begin
    if exists (select from pg_roles where rolname = 'fitfight_analytics') then
        grant select on private.account_auth to fitfight_analytics;
    end if;
end
$$;

commit;
