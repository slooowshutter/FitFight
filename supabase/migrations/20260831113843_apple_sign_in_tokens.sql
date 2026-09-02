create table private.apple_sign_in_tokens (
  user_id uuid primary key references public.profiles (user_id) on delete cascade,
  apple_subject text not null,
  encrypted_refresh_token text not null,
  encryption_iv text not null,
  encryption_tag text not null,
  updated_at timestamptz not null default now(),
  constraint apple_sign_in_tokens_subject_nonempty check (apple_subject <> ''),
  constraint apple_sign_in_tokens_token_nonempty check (encrypted_refresh_token <> ''),
  constraint apple_sign_in_tokens_iv_nonempty check (encryption_iv <> ''),
  constraint apple_sign_in_tokens_tag_nonempty check (encryption_tag <> '')
);

revoke all on table private.apple_sign_in_tokens from public, anon, authenticated;
grant all on table private.apple_sign_in_tokens to postgres, service_role;

alter table private.apple_sign_in_tokens enable row level security;
alter table private.apple_sign_in_tokens force row level security;
