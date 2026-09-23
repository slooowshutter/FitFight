begin;

alter table public.profiles drop constraint profiles_companion_id_check;
alter table public.profiles add constraint profiles_companion_id_check check (
    companion_id is null or companion_id in (
        'badger',
        'raccoon',
        'red-panda',
        'otter',
        'rabbit',
        'fox',
        'bear',
        'boar',
        'sloth',
        'dog',
        'goat',
        'turtle',
        'custom',
        'limited-pangolin',
        'limited-platypus',
        'limited-spotted-quoll',
        'limited-fennec-fox',
        'limited-musk-ox',
        'limited-kookaburra',
        'limited-porcupine',
        'limited-bharal',
        'limited-golden-snub-nosed-monkey',
        'limited-proboscis-monkey',
        'limited-tree-kangaroo',
        'limited-gila-monster',
        'limited-tarsier',
        'limited-maned-wolf',
        'limited-fire-salamander',
        'limited-serval-stroll',
        'limited-puffin',
        'limited-numbat-sprint',
        'limited-coati-snooze',
        'limited-galago',
        'limited-frilled-lizard',
        'limited-okapi',
        'limited-hoatzin',
        'limited-quokka',
        'limited-numbat-stride',
        'limited-sifaka',
        'limited-secretary-bird-stride',
        'limited-rock-hyrax',
        'limited-serval-sprint',
        'limited-banded-mongoose',
        'limited-axolotl',
        'limited-thorny-devil-stroll',
        'limited-coati-sprint',
        'limited-tamandua',
        'limited-paca',
        'limited-jerboa',
        'limited-thorny-devil-coffee',
        'limited-kakapo',
        'limited-secretary-bird-snooze',
        'limited-markhor'
    )
);

create table private.special_accounts (
    id uuid primary key default gen_random_uuid(),
    user_id uuid unique references auth.users(id) on delete set null,
    environment text not null check (environment in ('Sandbox', 'Production')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table private.special_editions (
    id uuid primary key default gen_random_uuid(),
    environment text not null check (environment in ('Sandbox', 'Production')),
    companion_id text not null,
    account_id uuid unique references private.special_accounts(id),
    state text not null default 'available' check (state in ('available', 'reserved', 'owned', 'revoked')),
    attempt_id uuid,
    original_transaction_id text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (environment, companion_id),
    unique (environment, original_transaction_id),
    check ((state = 'available') = (account_id is null)),
    check (state not in ('owned', 'revoked') or original_transaction_id is not null)
);

create table private.special_transactions (
    id uuid primary key default gen_random_uuid(),
    environment text not null check (environment in ('Sandbox', 'Production')),
    transaction_id text not null,
    original_transaction_id text not null,
    account_id uuid not null references private.special_accounts(id),
    companion_id text not null,
    outcome text not null check (outcome in ('owned', 'refunded', 'conflict')),
    signed_at timestamptz not null,
    purchase_at timestamptz not null,
    evidence jsonb not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (environment, transaction_id)
);
create index special_transactions_account_idx on private.special_transactions(account_id);
create index special_transactions_original_idx on private.special_transactions(environment, original_transaction_id);

alter table private.special_accounts enable row level security;
alter table private.special_editions enable row level security;
alter table private.special_transactions enable row level security;
revoke all on private.special_accounts, private.special_editions, private.special_transactions from public, anon, authenticated;

create trigger maintain_row_timestamps before update on private.special_accounts for each row execute function private.maintain_row_timestamps();
create trigger maintain_row_timestamps before update on private.special_editions for each row execute function private.maintain_row_timestamps();
create trigger maintain_row_timestamps before update on private.special_transactions for each row execute function private.maintain_row_timestamps();

insert into private.special_editions (environment, companion_id)
select environment, companion_id
from unnest(array['Sandbox', 'Production']) as environment
cross join unnest(array[
    'limited-pangolin',
    'limited-platypus',
    'limited-spotted-quoll',
    'limited-fennec-fox',
    'limited-musk-ox',
    'limited-kookaburra',
    'limited-porcupine',
    'limited-bharal',
    'limited-golden-snub-nosed-monkey',
    'limited-proboscis-monkey',
    'limited-tree-kangaroo',
    'limited-gila-monster',
    'limited-tarsier',
    'limited-maned-wolf',
    'limited-fire-salamander',
    'limited-serval-stroll',
    'limited-puffin',
    'limited-numbat-sprint',
    'limited-coati-snooze',
    'limited-galago',
    'limited-frilled-lizard',
    'limited-okapi',
    'limited-hoatzin',
    'limited-quokka',
    'limited-numbat-stride',
    'limited-sifaka',
    'limited-secretary-bird-stride',
    'limited-rock-hyrax',
    'limited-serval-sprint',
    'limited-banded-mongoose',
    'limited-axolotl',
    'limited-thorny-devil-stroll',
    'limited-coati-sprint',
    'limited-tamandua',
    'limited-paca',
    'limited-jerboa',
    'limited-thorny-devil-coffee',
    'limited-kakapo',
    'limited-secretary-bird-snooze',
    'limited-markhor'
]) as companion_id;

-- Integrity guard also covers older backend instances and direct profile writers.
create function private.require_special_ownership()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    if new.companion_id like 'limited-%' and (tg_op = 'INSERT' or new.companion_id is distinct from old.companion_id) then
        if not exists (
            select 1 from private.special_editions as edition
            join private.special_accounts as account on account.id = edition.account_id
            where account.user_id = new.user_id and edition.companion_id = new.companion_id
                and edition.environment = account.environment and edition.state = 'owned'
            for share of edition
        ) then
            raise exception 'special_purchase_required' using errcode = 'P0001';
        end if;
    end if;
    return new;
end;
$$;
revoke all on function private.require_special_ownership() from public, anon, authenticated;
create trigger require_special_ownership before insert or update of companion_id on public.profiles
    for each row execute function private.require_special_ownership();

commit;
