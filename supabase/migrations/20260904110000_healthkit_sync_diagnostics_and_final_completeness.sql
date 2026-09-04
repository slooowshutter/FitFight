-- Keep only the latest private HealthKit operational snapshot and expose only
-- Fight-scoped final completeness to accepted participants.

create table private.healthkit_sync_diagnostics (
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  connection_route text not null default 'healthkit',
  background_refresh_status text not null,
  delivery_registration_status text not null,
  last_observer_wake timestamptz,
  last_sync_attempt timestamptz,
  last_automatic_sync timestamptz,
  last_manual_sync timestamptz,
  last_trigger_context text,
  error_code text,
  app_version text not null,
  app_build text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, connection_route),
  constraint healthkit_diagnostics_route check (connection_route = 'healthkit'),
  constraint healthkit_diagnostics_background_refresh check (
    background_refresh_status in ('available', 'denied', 'restricted')
  ),
  constraint healthkit_diagnostics_delivery check (
    delivery_registration_status in ('enabled', 'unavailable')
  ),
  constraint healthkit_diagnostics_trigger check (
    last_trigger_context is null
    or last_trigger_context in ('observer', 'foreground', 'manual')
  ),
  constraint healthkit_diagnostics_error check (
    error_code is null
    or error_code in (
      'authentication_unavailable',
      'network_unavailable',
      'protected_data_unavailable',
      'attempt_expired',
      'healthkit_unavailable',
      'background_delivery_unavailable',
      'sync_failed'
    )
  )
);

alter table private.healthkit_sync_diagnostics enable row level security;
revoke all on table private.healthkit_sync_diagnostics from anon, authenticated, public;
grant all on table private.healthkit_sync_diagnostics to postgres, service_role;

alter table public.fight_members
  add column if not exists final_steps_complete boolean not null default false;
