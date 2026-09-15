-- Per-user notification toggles and fight-feed social outbox kinds.

create table private.notification_preferences (
    user_id uuid primary key references public.profiles (user_id) on delete cascade,
    feed_post boolean not null default true,
    post_comment boolean not null default true,
    comment_reply boolean not null default true,
    post_reaction boolean not null default true,
    challenge_reminder boolean not null default true,
    daily_status boolean not null default true,
    updated_at timestamptz not null default now()
);

alter table private.notification_preferences enable row level security;
revoke all on table private.notification_preferences from anon, authenticated, public;
grant all on table private.notification_preferences to postgres, service_role;

alter table private.notification_intents
    drop constraint notification_intents_kind;

alter table private.notification_intents
    add constraint notification_intents_kind check (
        kind in (
            'fight_ended',
            'grace_reminder',
            'fight_finalized',
            'daily_status',
            'feed_post',
            'post_comment',
            'comment_reply',
            'post_reaction'
        )
    );

alter table private.notification_intents
    drop constraint notification_intents_slot;

alter table private.notification_intents
    add constraint notification_intents_slot check (
        slot in ('t0', 't12', 't18', 't23', 'final', 'daily', 'event')
    );

alter table private.notification_intents
    add constraint notification_intents_social_alert_body check (
        kind not in ('feed_post', 'post_comment', 'comment_reply', 'post_reaction')
        or alert_body is not null
    );
