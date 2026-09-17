-- Keep workflow writes disabled until compatible readers have deployed and drained.
begin;

alter table public.feedback_posts
    add column workflow_status text not null default 'submitted'
    check (workflow_status in (
        'submitted', 'approved', 'building', 'reviewing',
        'testing', 'deployed', 'apple_approved', 'available'
    ));

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

commit;
