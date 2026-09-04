-- Persist the scoring version on each Fight member so finalized results stay
-- bound to the calculation that produced them.

alter table public.fight_members
  add column if not exists calculation_version integer not null default 1;
