-- Signed-in Users can submit feature requests and bugs. The phone never writes
-- these tables; TypeScript owns create, vote, report, and block.

create type public.request_kind as enum ('feature', 'bug');
create type public.request_status as enum ('open', 'planned', 'shipped');

create table public.feature_requests (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (user_id) on delete cascade,
  kind public.request_kind not null,
  status public.request_status not null default 'open',
  title text not null,
  body text not null,
  created_at timestamptz not null default now(),
  hidden_at timestamptz,
  constraint feature_requests_title_len check (char_length(title) between 1 and 80),
  constraint feature_requests_body_len check (char_length(body) between 1 and 500)
);

create table public.feature_request_votes (
  request_id uuid not null references public.feature_requests (id) on delete cascade,
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (request_id, user_id)
);

create table public.feature_request_reports (
  request_id uuid not null references public.feature_requests (id) on delete cascade,
  reporter_id uuid not null references public.profiles (user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (request_id, reporter_id)
);

create table public.feature_request_blocks (
  blocker_id uuid not null references public.profiles (user_id) on delete cascade,
  blocked_id uuid not null references public.profiles (user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint feature_request_blocks_not_self check (blocker_id <> blocked_id)
);

create index feature_requests_visible_created_idx
  on public.feature_requests (created_at desc)
  where hidden_at is null;

create index feature_request_votes_user_id_idx
  on public.feature_request_votes (user_id);

create index feature_request_reports_reporter_id_idx
  on public.feature_request_reports (reporter_id);

create index feature_request_blocks_blocker_id_idx
  on public.feature_request_blocks (blocker_id);

revoke all on table public.feature_requests from public, anon, authenticated;
revoke all on table public.feature_request_votes from public, anon, authenticated;
revoke all on table public.feature_request_reports from public, anon, authenticated;
revoke all on table public.feature_request_blocks from public, anon, authenticated;

grant all on table public.feature_requests to postgres, service_role;
grant all on table public.feature_request_votes to postgres, service_role;
grant all on table public.feature_request_reports to postgres, service_role;
grant all on table public.feature_request_blocks to postgres, service_role;

alter table public.feature_requests enable row level security;
alter table public.feature_request_votes enable row level security;
alter table public.feature_request_reports enable row level security;
alter table public.feature_request_blocks enable row level security;

alter table public.feature_requests force row level security;
alter table public.feature_request_votes force row level security;
alter table public.feature_request_reports force row level security;
alter table public.feature_request_blocks force row level security;
