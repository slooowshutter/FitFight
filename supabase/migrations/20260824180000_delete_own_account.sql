-- Apple requires in-app account deletion when accounts can be created.
-- Clients cannot use the secret key, so this is a self-only SECURITY DEFINER RPC.

create function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  keep_profile boolean;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  update public.profiles
     set deleted_at = now(),
         display_name = 'Deleted User',
         avatar_path = null,
         time_zone = null
   where user_id = uid;

  delete from auth.sessions where user_id = uid;
  delete from auth.refresh_tokens where user_id = uid;
  delete from auth.identities where user_id = uid;

  keep_profile := exists (
    select 1 from public.fights where owner_id = uid
    union all
    select 1 from public.fight_members where user_id = uid
    union all
    select 1 from public.friendships
     where requester_id = uid or addressee_id = uid
  );

  if not keep_profile then
    delete from auth.users where id = uid;
  end if;
end;
$$;

revoke all on function public.delete_own_account() from public, anon;
grant execute on function public.delete_own_account() to authenticated;
