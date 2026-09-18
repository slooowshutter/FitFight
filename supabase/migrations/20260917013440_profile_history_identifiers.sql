-- A shared Fight must not expose the same history identifier on different Profiles.
alter table private.fight_participation_records
    add column history_id uuid not null default gen_random_uuid(),
    add constraint fight_participation_history_id_key unique (history_id);
