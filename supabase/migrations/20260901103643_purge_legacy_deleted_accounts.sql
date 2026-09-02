-- allow-destructive
-- One-time hard purge for accounts deleted by the retired soft-delete flow.

create temporary table legacy_deleted_accounts (
  user_id uuid primary key
) on commit drop;

insert into legacy_deleted_accounts (user_id)
select user_id
from public.profiles
where deleted_at is not null;

do $$
declare
  account_count bigint;
  owned_fight_count bigint;
  other_membership_count bigint;
begin
  select count(*) into account_count
  from legacy_deleted_accounts;

  select count(*) into owned_fight_count
  from public.fights as fight
  join legacy_deleted_accounts as account
    on account.user_id = fight.owner_id;

  select count(*) into other_membership_count
  from public.fight_members as member
  join public.fights as fight
    on fight.id = member.fight_id
  join legacy_deleted_accounts as account
    on account.user_id = fight.owner_id
  where member.user_id <> account.user_id;

  raise notice
    'Purging % legacy deleted account(s), % owned Fight(s), and % other membership(s) in those Fights',
    account_count,
    owned_fight_count,
    other_membership_count;

  if exists (
    select 1
    from storage.objects as stored_object
    join legacy_deleted_accounts as account
      on stored_object.owner_id = account.user_id::text
      or (
        stored_object.bucket_id = 'provider-inbox'
        and stored_object.name like account.user_id::text || '/%'
      )
  ) then
    raise exception
      'Legacy deleted account cleanup blocked: remove target-owned Storage objects through the Storage API first';
  end if;

  if exists (
    select 1
    from public.data_sources as source
    join legacy_deleted_accounts as account
      on account.user_id = source.user_id
    where exists (
      select 1
      from public.fight_members as member
      where member.selected_source_id = source.id
        and not exists (
          select 1
          from legacy_deleted_accounts as member_account
          where member_account.user_id = member.user_id
        )
        and not exists (
          select 1
          from public.fights as owned_fight
          join legacy_deleted_accounts as owner_account
            on owner_account.user_id = owned_fight.owner_id
          where owned_fight.id = member.fight_id
        )
    )
      or exists (
        select 1
        from private.metric_observations as observation
        where observation.source_id = source.id
          and not exists (
            select 1
            from legacy_deleted_accounts as observation_account
            where observation_account.user_id = observation.user_id
          )
      )
      or exists (
        select 1
        from private.provider_uploads as upload
        where upload.source_id = source.id
          and not exists (
            select 1
            from legacy_deleted_accounts as upload_account
            where upload_account.user_id = upload.user_id
          )
      )
      or exists (
        select 1
        from private.provider_events as event
        where event.source_id = source.id
          and not exists (
            select 1
            from legacy_deleted_accounts as event_account
            where event_account.user_id = event.user_id
          )
      )
      or exists (
        select 1
        from public.metric_days as metric_day
        where metric_day.source_id = source.id
          and not exists (
            select 1
            from legacy_deleted_accounts as metric_day_account
            where metric_day_account.user_id = metric_day.user_id
          )
      )
      or exists (
        select 1
        from private.fight_score_snapshots as snapshot
        where snapshot.source_id = source.id
          and not exists (
            select 1
            from legacy_deleted_accounts as snapshot_account
            where snapshot_account.user_id = snapshot.user_id
          )
          and not exists (
            select 1
            from public.fights as owned_fight
            join legacy_deleted_accounts as owner_account
              on owner_account.user_id = owned_fight.owner_id
            where owned_fight.id = snapshot.fight_id
          )
      )
  ) then
    raise exception
      'Legacy deleted account cleanup blocked: an active account references a target-owned data source';
  end if;

  if exists (
    select 1
    from private.provider_uploads as upload
    join legacy_deleted_accounts as account
      on account.user_id = upload.user_id
    where exists (
      select 1
      from private.provider_events as event
      where event.upload_id = upload.upload_id
        and not exists (
          select 1
          from legacy_deleted_accounts as event_account
          where event_account.user_id = event.user_id
        )
    )
      or exists (
        select 1
        from private.metric_observations as observation
        where observation.upload_id = upload.upload_id
          and not exists (
            select 1
            from legacy_deleted_accounts as observation_account
            where observation_account.user_id = observation.user_id
          )
      )
      or exists (
        select 1
        from private.fight_score_snapshots as snapshot
        where snapshot.upload_id = upload.upload_id
          and not exists (
            select 1
            from legacy_deleted_accounts as snapshot_account
            where snapshot_account.user_id = snapshot.user_id
          )
          and not exists (
            select 1
            from public.fights as owned_fight
            join legacy_deleted_accounts as owner_account
              on owner_account.user_id = owned_fight.owner_id
            where owned_fight.id = snapshot.fight_id
          )
      )
  ) then
    raise exception
      'Legacy deleted account cleanup blocked: an active account references a target-owned provider upload';
  end if;
end;
$$;

delete from public.fights as fight
using legacy_deleted_accounts as account
where fight.owner_id = account.user_id;

delete from private.fight_score_snapshots as snapshot
using legacy_deleted_accounts as account
where snapshot.user_id = account.user_id;

delete from private.metric_observations as observation
using legacy_deleted_accounts as account
where observation.user_id = account.user_id;

delete from private.provider_events as event
using legacy_deleted_accounts as account
where event.user_id = account.user_id;

delete from private.provider_uploads as upload
using legacy_deleted_accounts as account
where upload.user_id = account.user_id;

delete from private.healthkit_step_source_days as source_day
using legacy_deleted_accounts as account
where source_day.user_id = account.user_id;

delete from private.healthkit_step_sample_deletions as sample_deletion
using legacy_deleted_accounts as account
where sample_deletion.user_id = account.user_id;

delete from private.healthkit_step_samples as sample
using legacy_deleted_accounts as account
where sample.user_id = account.user_id;

delete from private.healthkit_step_syncs as sync
using legacy_deleted_accounts as account
where sync.user_id = account.user_id;

delete from public.metric_days as metric_day
using legacy_deleted_accounts as account
where metric_day.user_id = account.user_id;

delete from public.step_days as step_day
using legacy_deleted_accounts as account
where step_day.user_id = account.user_id;

delete from public.fight_members as member
using legacy_deleted_accounts as account
where member.user_id = account.user_id;

delete from public.fight_invites as invite
using legacy_deleted_accounts as account
where invite.invited_user_id = account.user_id;

delete from public.friendships as friendship
using legacy_deleted_accounts as account
where friendship.requester_id = account.user_id
   or friendship.addressee_id = account.user_id;

delete from public.data_sources as source
using legacy_deleted_accounts as account
where source.user_id = account.user_id;

delete from auth.sessions as session
using legacy_deleted_accounts as account
where session.user_id::text = account.user_id::text;

delete from auth.refresh_tokens as refresh_token
using legacy_deleted_accounts as account
where refresh_token.user_id::text = account.user_id::text;

delete from auth.identities as identity
using legacy_deleted_accounts as account
where identity.user_id::text = account.user_id::text;

delete from auth.users as auth_user
using legacy_deleted_accounts as account
where auth_user.id = account.user_id;
