begin;
select plan(6);

select has_column('public', 'profiles', 'companion_id', 'profiles can store a companion');
select has_column('public', 'profiles', 'companion_prompt', 'profiles can store a custom companion description');

select is(
    has_column_privilege('authenticated', 'public.profiles', 'companion_id', 'UPDATE'),
    false,
    'clients cannot write companion_id directly'
);

select is(
    has_column_privilege('authenticated', 'public.profiles', 'companion_prompt', 'UPDATE'),
    false,
    'clients cannot write companion_prompt directly'
);

select ok(
    exists (
        select 1 from pg_constraint
        where conrelid = 'public.profiles'::regclass
            and conname = 'profiles_companion_id_check'
            and pg_get_constraintdef(oid) like '%custom%'
    ),
    'companion ids allow custom'
);

select ok(
    exists (
        select 1 from pg_constraint
        where conrelid = 'public.profiles'::regclass
            and conname = 'profiles_companion_prompt_check'
    ),
    'custom companion prompts are constrained'
);

select * from finish();
rollback;
