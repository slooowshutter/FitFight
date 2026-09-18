begin;
select plan(11);

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

select has_table('private', 'companion_libraries', 'saved descriptions stay in a private library');
select is(
    has_table_privilege('authenticated', 'private.companion_libraries', 'SELECT'),
    false,
    'clients cannot read saved descriptions directly'
);
select is(
    has_table_privilege('authenticated', 'private.companion_libraries', 'UPDATE'),
    false,
    'clients cannot overwrite saved descriptions directly'
);
select is(
    has_function_privilege('authenticated', 'private.remember_companion_prompt()', 'EXECUTE'),
    false,
    'capture is an internal trigger, not an app RPC'
);
select ok(
    (select relrowsecurity from pg_class where oid = 'private.companion_libraries'::regclass),
    'the private library also has RLS enabled'
);

select * from finish();
rollback;
