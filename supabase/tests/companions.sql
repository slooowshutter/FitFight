begin;
select plan(3);

select has_column('public', 'profiles', 'companion_id', 'profiles can store a companion');

select is(
  has_column_privilege('authenticated', 'public.profiles', 'companion_id', 'UPDATE'),
  false,
  'clients cannot write companion_id directly'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_companion_id_check'
  ),
  'companion ids are constrained'
);

select * from finish();
rollback;
