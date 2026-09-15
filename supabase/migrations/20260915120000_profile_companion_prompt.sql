alter table public.profiles
  add column companion_prompt text;

alter table public.profiles
  drop constraint profiles_companion_id_check;

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
      'turtle',
      'custom'
    )
  );

alter table public.profiles
  add constraint profiles_companion_prompt_check
  check (
    (
      companion_id is distinct from 'custom'
      and companion_prompt is null
    )
    or (
      companion_id = 'custom'
      and companion_prompt is not null
      and char_length(btrim(companion_prompt)) between 1 and 1000
    )
  );
