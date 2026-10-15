-- Monthly friend fights: every accepted friendship has one repeating 1v1 Steps series whose
-- rounds run for a calendar month. The pair columns guarantee one series per friendship, so
-- unfriending pauses it and refriending resumes the same series with its history. Nothing is
-- deleted: an ended round is cancelled and its series paused. Deleting an account clears the
-- pair on the friend's series first, so the friend keeps it.

alter table public.fight_series
    add column friend_low uuid references public.profiles (user_id),
    add column friend_high uuid references public.profiles (user_id),
    add constraint fight_series_friend_pair check (
        (friend_low is null and friend_high is null)
        or (friend_low is not null and friend_high is not null and friend_low < friend_high)
    );

create unique index fight_series_friend_pair_key
    on public.fight_series (friend_low, friend_high)
    where friend_low is not null;

alter table public.fights
    add column friends boolean not null default false;

comment on column public.fight_series.friend_low is
    'Friend fight pair, lower user id. Set with friend_high; one series per friendship.';
comment on column public.fight_series.friend_high is
    'Friend fight pair, higher user id. Set with friend_low; one series per friendship.';
comment on column public.fights.friends is
    'Friend round: calendar-month window, scored from each member''s stored daily Steps, and hidden from builds that do not ask for friend rounds.';
