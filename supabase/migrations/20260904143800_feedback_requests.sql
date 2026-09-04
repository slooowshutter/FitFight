-- Signed-in Users can read the public bugs and feature-request board.
-- Creates, votes, and comments are server-owned TypeScript commands.

create type public.feedback_kind as enum ('bug', 'feature');

create table public.feedback_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (user_id) on delete cascade,
  kind public.feedback_kind not null,
  title text not null,
  body text not null,
  created_at timestamptz not null default now(),
  constraint feedback_posts_title_len check (char_length(title) between 8 and 80),
  constraint feedback_posts_body_len check (char_length(body) between 20 and 2000)
);

create table public.feedback_votes (
  post_id uuid not null references public.feedback_posts (id) on delete cascade,
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table public.feedback_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.feedback_posts (id) on delete cascade,
  author_id uuid not null references public.profiles (user_id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  constraint feedback_comments_body_len check (char_length(body) between 2 and 500)
);

create index feedback_posts_kind_votes_idx
  on public.feedback_posts (kind, created_at desc);

create index feedback_votes_user_idx
  on public.feedback_votes (user_id);

create index feedback_comments_post_idx
  on public.feedback_comments (post_id, created_at);

grant select on public.feedback_posts to authenticated;
grant select on public.feedback_comments to authenticated;
revoke all on table public.feedback_votes from anon, authenticated, public;
grant all on table public.feedback_posts to postgres, service_role;
grant all on table public.feedback_votes to postgres, service_role;
grant all on table public.feedback_comments to postgres, service_role;

alter table public.feedback_posts enable row level security;
alter table public.feedback_votes enable row level security;
alter table public.feedback_comments enable row level security;
alter table public.feedback_posts force row level security;
alter table public.feedback_votes force row level security;
alter table public.feedback_comments force row level security;

create policy feedback_posts_select_signed_in
  on public.feedback_posts
  for select
  to authenticated
  using (true);

create policy feedback_comments_select_signed_in
  on public.feedback_comments
  for select
  to authenticated
  using (true);
