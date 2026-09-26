-- Mention alerts name the person. No scores.

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
            'post_reaction',
            'fight_invite',
            'mention'
        )
    );

alter table private.notification_intents
    drop constraint notification_intents_social_alert_body;

alter table private.notification_intents
    add constraint notification_intents_social_alert_body check (
        kind not in (
            'feed_post',
            'post_comment',
            'comment_reply',
            'post_reaction',
            'fight_invite',
            'mention'
        )
        or alert_body is not null
    );
