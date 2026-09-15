alter table public.profiles
  add column companion_id text;

alter table public.profiles
  add constraint profiles_companion_id_check
  check (
    companion_id is null
    or companion_id in (
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
      'turtle'
    )
  );
