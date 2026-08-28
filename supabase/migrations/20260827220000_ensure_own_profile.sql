-- If Auth created a user but the profile trigger missed, or the profile was
-- soft-deleted, the phone was stuck on “Loading your account”. This RPC
-- creates or undeletes the signed-in user’s row.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  generated_handle text;
begin
  generated_handle := 'user_' || right(replace(new.id::text, '-', ''), 12);
  insert into public.profiles (user_id, handle, display_name)
  values (
    new.id,
    generated_handle,
    coalesce(
      nullif(new.raw_user_meta_data->>'full_name', ''),
      nullif(new.raw_user_meta_data->>'name', ''),
      'Fighter'
    )
  )
  on conflict (user_id) do update
    set deleted_at = null,
        display_name = case
          when public.profiles.display_name in ('Deleted User', '') then excluded.display_name
          else public.profiles.display_name
        end;
  return new;
end;
$$;

create or replace function public.ensure_own_profile()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  generated_handle text;
  meta jsonb;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  if exists (select 1 from public.profiles where user_id = uid and deleted_at is null) then
    return;
  end if;

  select raw_user_meta_data into meta from auth.users where id = uid;
  generated_handle := 'user_' || right(replace(uid::text, '-', ''), 12);

  insert into public.profiles (user_id, handle, display_name)
  values (
    uid,
    generated_handle,
    coalesce(
      nullif(meta->>'full_name', ''),
      nullif(meta->>'name', ''),
      'Fighter'
    )
  )
  on conflict (user_id) do update
    set deleted_at = null,
        display_name = case
          when public.profiles.display_name in ('Deleted User', '') then excluded.display_name
          else public.profiles.display_name
        end;
end;
$$;

revoke all on function public.ensure_own_profile() from public, anon;
grant execute on function public.ensure_own_profile() to authenticated;
