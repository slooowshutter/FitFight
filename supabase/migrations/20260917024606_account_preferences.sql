create table private.account_preferences (
    user_id uuid primary key references public.profiles (user_id) on delete cascade,
    language text not null default 'system' check (language in ('system', 'en', 'fr')),
    appearance text not null default 'system' check (appearance in ('system', 'light', 'dark')),
    updated_at timestamptz not null default now()
);

alter table private.account_preferences enable row level security;
revoke all on table private.account_preferences from anon, authenticated, public;
grant all on table private.account_preferences to postgres, service_role;
