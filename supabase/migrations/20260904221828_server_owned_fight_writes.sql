-- Membership acceptance grants access to health summaries; only server commands may write it.
revoke insert, update, delete
  on public.fights, public.fight_members, public.data_sources
  from public, anon, authenticated;

drop policy if exists fights_insert_own on public.fights;
drop policy if exists fights_update_owner_or_due on public.fights;
drop policy if exists fight_members_insert_owner on public.fight_members;
drop policy if exists fight_members_update_own on public.fight_members;
drop policy if exists data_sources_insert_own on public.data_sources;
drop policy if exists data_sources_update_own on public.data_sources;
