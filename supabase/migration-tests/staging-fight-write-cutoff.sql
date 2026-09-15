-- Reproduce staging, where the original server-owned-write migration already ran.
revoke all (owner_id, name, state, starts_at, ends_at, time_zone, metric,
  outcome_rule, goal_policy, default_goal_value, stake_kind, stake_minor, currency, action_text)
  on public.fights from public, anon, authenticated;
revoke all (fight_id, user_id, state, accepted_at)
  on public.fight_members from public, anon, authenticated;
drop policy fights_insert_legacy_owner on public.fights;
drop policy fight_members_insert_legacy_owner on public.fight_members;
drop policy fight_members_update_legacy_invitee on public.fight_members;
