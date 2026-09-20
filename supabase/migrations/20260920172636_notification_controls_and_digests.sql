-- Retain released preference fields and outbox kinds throughout the rollout.
alter table private.notification_preferences
    add column enabled boolean not null default true,
    add column fight_invite boolean not null default true,
    add column ending_24h boolean not null default true,
    add column ending_week boolean not null default false,
    add column fight_ended boolean not null default false,
    add column final_sync boolean not null default true,
    add column fight_finalized boolean not null default true,
    add column mention boolean not null default true,
    alter column feed_post set default false,
    alter column daily_status set default false;

-- Existing explicit opt-outs survive; saved feed and daily choices are preserved.
update private.notification_preferences
set final_sync = challenge_reminder,
    fight_finalized = challenge_reminder,
    ending_24h = challenge_reminder;

create function private.maintain_legacy_notification_preferences()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if tg_op = 'INSERT' then
        if not new.challenge_reminder then
            new.fight_ended := false;
            new.final_sync := false;
            new.fight_finalized := false;
        end if;
    elsif new.challenge_reminder is distinct from old.challenge_reminder
        and new.fight_ended is not distinct from old.fight_ended
        and new.final_sync is not distinct from old.final_sync
        and new.fight_finalized is not distinct from old.fight_finalized then
        new.fight_ended := new.challenge_reminder;
        new.final_sync := new.challenge_reminder;
        new.fight_finalized := new.challenge_reminder;
    end if;
    new.challenge_reminder := new.fight_ended or new.final_sync or new.fight_finalized;
    return new;
end;
$$;

create trigger maintain_legacy_notification_preferences
before insert or update on private.notification_preferences
for each row execute function private.maintain_legacy_notification_preferences();
revoke all on function private.maintain_legacy_notification_preferences() from public, anon, authenticated;

alter table private.notification_intents
    add column actor_id uuid references public.profiles (user_id) on delete set null,
    add column post_id uuid references public.fight_posts (id) on delete set null,
    add column comment_id uuid references public.fight_post_comments (id) on delete set null,
    add column digest_on date,
    add column digest_id uuid references private.notification_intents (id) on delete set null;

alter table private.notification_intents drop constraint notification_intents_kind;
alter table private.notification_intents add constraint notification_intents_kind check (
    kind in ('fight_ended', 'grace_reminder', 'fight_finalized', 'daily_status',
        'feed_post', 'post_comment', 'comment_reply', 'post_reaction', 'fight_invite',
        'mention', 'ending_24h', 'ending_week', 'final_sync', 'social_digest')
);
alter table private.notification_intents drop constraint notification_intents_slot;
alter table private.notification_intents add constraint notification_intents_slot check (
    slot in ('t0', 't12', 't18', 't23', 'final', 'daily', 'event', 'before_24h', 'before_week')
);

create index notification_digest_events_idx
on private.notification_intents (digest_id) where digest_id is not null;
create index notification_digest_due_idx
on private.notification_intents (user_id, digest_on, not_before)
where status = 'pending' and kind in ('feed_post', 'post_reaction');

update private.notification_intents
set status = 'skipped', skip_reason = 'superseded', processed_at = now()
where status = 'pending' and kind = 'grace_reminder';
