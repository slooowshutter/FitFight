begin;
select plan(4);

select has_table('public', 'fight_post_channels', 'posts can belong to several fights');
select has_column('public', 'fight_posts', 'broadcast', 'broadcast marks a post to every fight the author chose');
select has_column('public', 'fight_series', 'suggested', 'Marc can flag a series for New');
select is(
  has_table_privilege('authenticated', 'public.fight_post_channels', 'INSERT'),
  false,
  'clients cannot insert post channels'
);

select * from finish();
rollback;
