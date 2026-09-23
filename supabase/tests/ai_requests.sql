begin;
select plan(43);

select ok(c.relrowsecurity, c.relname || ' has RLS enabled')
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'private' and c.relname in ('ai_requests', 'ai_caller_windows', 'ai_provider_budget', 'ai_credit_balances', 'ai_balance_events', 'ai_http_logs', 'ai_library_images')
order by c.relname;

select ok(not has_table_privilege(role_name, 'private.' || table_name, 'SELECT,INSERT,UPDATE,DELETE'),
    role_name || ' cannot read or mutate ' || table_name)
from unnest(array['anon', 'authenticated', 'service_role', 'fitfight_backend_reader']) as role_name
cross join unnest(array['ai_requests', 'ai_caller_windows', 'ai_provider_budget', 'ai_credit_balances', 'ai_balance_events', 'ai_http_logs', 'ai_library_images']) as table_name;

select ok(not has_function_privilege(role_name, 'private.' || function_name || '()', 'EXECUTE'),
    role_name || ' cannot invoke ' || function_name)
from unnest(array['anon', 'authenticated', 'service_role', 'fitfight_backend_reader']) as role_name
cross join unnest(array['guard_ai_balance_history', 'check_ai_balance_chain']) as function_name;

select * from finish();
rollback;
