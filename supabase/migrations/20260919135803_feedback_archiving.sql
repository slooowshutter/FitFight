alter table public.feedback_posts
    add column archived boolean not null default false,
    add column archive_reason text,
    add constraint feedback_archive_reason_length
        check (archive_reason is null or char_length(archive_reason) <= 280),
    add constraint feedback_archive_reason_state
        check (archived or archive_reason is null);

-- Feedback writes already belong to the backend. Existing client grants stay intact.
create index feedback_posts_archive_created_idx
    on public.feedback_posts (archived, created_at desc);
