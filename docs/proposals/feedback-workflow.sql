-- Deferred by Marc on 18 Sep 2026. Design reference only, not an executable migration.
-- Proposal only. No new tables and no hosted database changes.
-- Enable system-comment writes only after compatible backend readers have deployed.

begin;

alter table public.feedback_posts
    add column workflow_status text not null default 'submitted'
    check (workflow_status in (
        'submitted', 'approved', 'building', 'reviewing',
        'testing', 'deployed', 'apple_approved', 'available'
    ));

-- System messages have no invented User account. Approval messages can retain
-- the real approving User as author_id so their name opens the shared Profile.
alter table public.feedback_comments
    alter column author_id drop not null,
    add column workflow_status text
        check (workflow_status in (
            'submitted', 'approved', 'building', 'reviewing',
            'testing', 'deployed', 'apple_approved', 'available'
        )),
    add constraint feedback_comments_user_identity check (
        workflow_status is not null or author_id is not null
    );

-- Existing RLS and server-only write grants stay in place.
-- The existing (post_id, created_at) index serves the discussion and its history.
-- The backend updates the request and inserts its system comment in one transaction.

commit;
