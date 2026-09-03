-- Last successful Apple Health upload for this membership, readable by Fight peers.

alter table public.fight_members
  add column if not exists last_synced_at timestamptz;

update public.fight_members as member
set last_synced_at = snapshot.synced_at
from (
  select fight_id, user_id, max(created_at) as synced_at
  from private.fight_score_snapshots
  group by fight_id, user_id
) as snapshot
where member.fight_id = snapshot.fight_id
  and member.user_id = snapshot.user_id
  and member.last_synced_at is null;

update public.fight_members as member
set last_synced_at = source.last_success_at
from public.data_sources as source
where member.selected_source_id = source.id
  and member.last_synced_at is null
  and source.last_success_at is not null;

update public.fight_members as member
set last_synced_at = source.last_success_at
from public.data_sources as source
where source.user_id = member.user_id
  and source.provider = 'apple_health'
  and source.connection_route = 'healthkit'
  and member.state = 'accepted'
  and member.last_synced_at is null
  and source.last_success_at is not null;
