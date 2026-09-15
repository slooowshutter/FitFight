-- Temporary private checkpoints for the authorized cloud rehearsal.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('release-transfer-rehearsal', 'release-transfer-rehearsal', false, 104857600, array['application/json'])
on conflict (id) do nothing;

select id, public, file_size_limit
from storage.buckets
where id = 'release-transfer-rehearsal';
