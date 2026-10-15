-- Friend rounds send one batched sync reminder and one monthly results push per person.
alter table private.notification_intents drop constraint notification_intents_kind;
alter table private.notification_intents add constraint notification_intents_kind check (
    kind in ('fight_ended', 'grace_reminder', 'fight_finalized', 'daily_status',
        'feed_post', 'post_comment', 'comment_reply', 'post_reaction', 'fight_invite',
        'mention', 'ending_24h', 'ending_week', 'final_sync', 'social_digest',
        'friends_sync', 'friends_results')
);
