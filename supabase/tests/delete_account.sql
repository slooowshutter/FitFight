begin;
select plan(4);

select ok(
  to_regprocedure('public.delete_own_account()') is null,
  'account deletion is not exposed as a database RPC'
);
select is(
  has_table_privilege('anon', 'public.profiles', 'DELETE'),
  false,
  'anonymous clients cannot delete profiles'
);
select is(
  has_table_privilege('authenticated', 'public.profiles', 'DELETE'),
  false,
  'authenticated clients cannot delete profiles'
);
select is(
  has_column_privilege('authenticated', 'public.profiles', 'deleted_at', 'UPDATE'),
  false,
  'authenticated clients cannot mark accounts deleted directly'
);

select * from finish();
rollback;
