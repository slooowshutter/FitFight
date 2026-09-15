-- Chart history belongs to the same immutable upload revision as its scored total.
alter table private.fight_score_snapshots add column step_checkpoints jsonb;

alter table private.fight_score_snapshots add constraint fight_step_checkpoints_array
  check (step_checkpoints is null or jsonb_typeof(step_checkpoints) = 'array');

create index fight_score_snapshots_member_latest
  on private.fight_score_snapshots
    (fight_id, user_id, source_id, cutoff_at desc, created_at desc, id desc);

grant select (id, fight_id, user_id, source_id, cutoff_at, value, is_final, created_at, step_checkpoints)
  on private.fight_score_snapshots to fitfight_backend_reader;

create policy fight_score_snapshots_backend_roster
  on private.fight_score_snapshots for select to fitfight_backend_reader
  using (private.current_user_is_roster_member(fight_id));

create or replace function private.protect_final_fight_snapshots()
returns trigger
language plpgsql
as $$
begin
  if old.is_final and not private.allow_score_correction() then
    new.value := old.value;
    new.input_hash := old.input_hash;
    new.calculation_version := old.calculation_version;
    new.cutoff_at := old.cutoff_at;
    new.is_final := true;
    new.source_id := old.source_id;
    new.step_checkpoints := old.step_checkpoints;
  end if;
  return new;
end;
$$;
