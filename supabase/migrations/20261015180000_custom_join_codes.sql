-- Fight owners can pick their own code: 4 to 12 letters or digits. Random codes keep the
-- 4-character alphabet without lookalikes. The backend stores codes uppercase.
alter table public.fight_series
    drop constraint fight_series_join_code_format;

alter table public.fight_series
    add constraint fight_series_join_code_format check (
        join_code ~ '^[0-9A-Z]{4,12}$'
    );
