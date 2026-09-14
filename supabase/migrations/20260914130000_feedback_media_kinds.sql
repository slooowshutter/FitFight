-- Photos, videos, and other files on Bugs & requests.
alter type public.media_kind add value if not exists 'file';
alter type public.media_purpose add value if not exists 'feedback';
