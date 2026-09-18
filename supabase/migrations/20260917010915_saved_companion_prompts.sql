begin;

-- Keep the backfill and capture trigger atomic with concurrent profile writes.
lock table public.profiles in share row exclusive mode;

create table private.companion_libraries (
    user_id uuid primary key references public.profiles(user_id) on delete cascade,
    prompts text[] not null default '{}'
);

alter table private.companion_libraries enable row level security;
revoke all on private.companion_libraries from public, anon, authenticated;
grant all on private.companion_libraries to postgres, service_role;

insert into private.companion_libraries (user_id, prompts)
select user_id, array[companion_prompt]
from public.profiles
where companion_prompt is not null and deleted_at is null;

-- Capture old backend writes too, while companion_prompt keeps its existing contract.
create function private.remember_companion_prompt()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into private.companion_libraries (user_id, prompts)
    values (new.user_id, array[new.companion_prompt])
    on conflict (user_id) do update
    set prompts = array[new.companion_prompt]
        || array_remove(private.companion_libraries.prompts, new.companion_prompt);
    return new;
end;
$$;

revoke all on function private.remember_companion_prompt() from public, anon, authenticated;

create trigger remember_companion_prompt
after insert or update of companion_prompt on public.profiles
for each row
when (new.companion_prompt is not null and new.deleted_at is null)
execute function private.remember_companion_prompt();

commit;
